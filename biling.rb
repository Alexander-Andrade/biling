require 'net/http'
require 'json'
require 'nokogiri'
require 'rubygems'
require 'mechanize'
require 'parallel'
require 'timeout'


class GoogleTranslate
  attr_reader :current_proxy_ind

  def initialize(proxies, timeout = 7)
    @proxies = proxies
    @timeout = timeout
    @current_proxy_ind = 0
    @agent = Mechanize.new

    init_proxy
  end

  def init_proxy
    @agent.keep_alive = false
    @agent.open_timeout = @timeout
    @agent.read_timeout = @timeout
  end

  def set_proxy
    host, port = @proxies[@current_proxy_ind]
    @agent.set_proxy host, port
  end

  def random_proxy
    @current_proxy_ind = Random.rand(@proxies.length)
    set_proxy
  end

  def translate(text)
    text = text.gsub(/[^[:ascii:]]/, '')
    data = nil
    page = nil
    begin
      Timeout::timeout(@timeout) do
        page = @agent.get("https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ru&dt=t&q=#{text}")
      end
      response = JSON.parse(page.body)
      data = response[0].map { |res| res[0] }.join
    rescue => e
      # p e
    end

    data
  end
end


class Bilingual
  def initialize(file_to_translate, result_file, batch_size = 16)
    @file_to_translate = file_to_translate
    @result_file = result_file
    @batch_size = batch_size
    @proxies = proxies_list
    @translators = (0...@batch_size).map { |_| GoogleTranslate.new(@proxies) }
  end

  def add_translation_node(translation, node, doc)
    translated_p = Nokogiri::XML::Node.new 'p', doc
    emphasis_node = Nokogiri::XML::Node.new 'emphasis', doc
    translated_p.add_child emphasis_node
    empty_line = Nokogiri::XML::Node.new 'empty-line', doc
    emphasis_node.content = translation
    node.add_next_sibling(empty_line)
    node.add_next_sibling(translated_p)
  end

  def proxies_list
    File.readlines('proxies.txt').map do |line|
      parts = line.split(':')
      [parts[0].strip, parts[1].strip]
    end
  end

  def next_node_ind(node_ind, batch_size, cur_batch_size, iter_to)
    if node_ind + batch_size < iter_to
      node_ind + batch_size - cur_batch_size
    elsif node_ind < iter_to
      node_ind + iter_to - node_ind
    else
      node_ind
    end
  end

  def run
    doc = File.open(@file_to_translate) { |f| Nokogiri::XML(f) }
    paragraphs = doc.css('p')

    iter_to = paragraphs.length - 1
    batch = (0...@batch_size).to_a
    node_ind = @batch_size

    until batch.empty?
      @translators.each(&:random_proxy)
      # p "proxies: #{@translators.map(&:current_proxy_ind)}"
      start = Time.now
      results = Parallel.map(batch, in_threads: @batch_size) do |node_ind|
        t = @translators[node_ind % @batch_size].translate(paragraphs[node_ind].content)
        # p "translator: #{node_ind % @batch_size} node_id: #{node_ind} text: #{paragraphs[node_ind].content}, translation: #{t}"
        # t
      end
      p "time: #{Time.now - start}"

      result_success_ids = results.each_index.select { |i| results[i].is_a? String }
      success_ids = batch.values_at(*result_success_ids)
      p batch
      p success_ids
      # p results
      batch -= success_ids

      success_ids.each { |node_ind| add_translation_node(results[node_ind], paragraphs[node_ind], doc) }

      new_node_ind = next_node_ind(node_ind, @batch_size, batch.length, iter_to)
      batch += (node_ind...new_node_ind).to_a
      node_ind = new_node_ind

      p node_ind * 100 / iter_to.to_f
    end

    File.write(@result_file, doc.to_xml)
  end
end


if ARGV.length < 2
  puts "Too few arguments"
  exit
end

file_to_translate = ARGV[0]
result_file = ARGV[1]
service = ARGV[2] || 'google'


bilingual = Bilingual.new(file_to_translate, result_file, 16)
bilingual.run
