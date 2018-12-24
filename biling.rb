require 'net/http'
require 'json'
require 'nokogiri'
require 'rubygems'
require 'mechanize'


class YandexTranslate
  def initialize(key)
    @key = key
  end

  def translate(text)
    text = text.gsub(/[^[:ascii:]]/, '')
    uri = URI("https://translate.yandex.net/api/v1.5/tr.json/translate?key=#{@key}&text=#{text}&lang=ru")
    response = JSON.parse(Net::HTTP.get(uri))
    response['text'][0]
  end
end


class GoogleTranslate
  attr_reader :proxy_stat

  def initialize(proxies, calls_per_proxy)
    @proxies = proxies
    @calls_per_proxy = calls_per_proxy
    @current_proxy_ind = 0
    @calls_counter = 0
    @agent = Mechanize.new
    @proxy_stat = Hash.new { |hash, key| hash[key] = { hits: 0, misses: 0 } }
    init_proxy
    set_proxy
  end

  def init_proxy
    @agent.keep_alive = false
    @agent.open_timeout = 10
    @agent.read_timeout = 10
  end

  def set_proxy
    host, port = @proxies[@current_proxy_ind]
    @agent.set_proxy host, port
  end

  def round_robin_proxy
    @calls_counter += 1
    return if @calls_counter < @calls_per_proxy - 1

    next_proxy
  end

  def next_proxy
    @calls_counter = 0
    @current_proxy_ind = @current_proxy_ind < @proxies.length - 2 ? @current_proxy_ind + 1 : 0
    set_proxy
  end

  def translate(text)
    text = text.gsub(/[^[:ascii:]]/, '')
    data = nil

    while true
      begin
        page = @agent.get("https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ru&dt=t&q=#{text}")
        response = JSON.parse(page.body)

        @proxy_stat[@current_proxy_ind][:hits] += 1

        data = response[0].map { |res| res[0] }.join
        p data
        break
      rescue => e
        p "#{e}, proxy_id: #{@current_proxy_ind}"

        @proxy_stat[@current_proxy_ind][:misses] += 1

        if @current_proxy_ind == @proxies.length - 1
          uri = URI("https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ru&dt=t&q=#{text}")
          response = JSON.parse(Net::HTTP.get(uri))
          data = response[0][0][0]
          break
        end

        next_proxy
      end
    end
    p "proxy_id: #{@current_proxy_ind}"
    round_robin_proxy

    data
  end
end

proxies = []

File.readlines('proxies.txt').each do |line|
  parts = line.split(',')
  proxies.push([parts[0].strip, parts[1].strip])
end

translator = GoogleTranslate.new(proxies, 10)

if ARGV.length < 2
  puts "Too few arguments"
  exit
end


file_to_translate = ARGV[0]
result_file = ARGV[1]
service = ARGV[2] || 'google'

doc = File.open(file_to_translate) { |f| Nokogiri::XML(f) }
paragraphs = doc.css('p')

iter_to = paragraphs.length - 1
(0..iter_to).each do |i|
  translated_p = Nokogiri::XML::Node.new 'p', doc
  emphasis_node = Nokogiri::XML::Node.new 'emphasis', doc
  translated_p.add_child emphasis_node
  empty_line = Nokogiri::XML::Node.new 'empty-line', doc
  emphasis_node.content = translator.translate(paragraphs[i].content)
  paragraphs[i].add_next_sibling(empty_line)
  paragraphs[i].add_next_sibling(translated_p)
  p translator.proxy_stat if i % 20 == 0
  p i * 100 / iter_to.to_f
end

File.write(result_file, doc.to_xml)
