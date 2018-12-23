require 'net/http'
require 'json'
require 'nokogiri'


def translate(text)
  text = text.gsub(/[^[:ascii:]]/, '')
  key = 'trnsl.1.1.20181222T190255Z.5f681e8011285a14.931279157d16121692edf18e8ad5665d98b55e84'
  uri = URI("https://translate.yandex.net/api/v1.5/tr.json/translate?key=#{key}&text=#{text}&lang=ru")
  response = JSON.parse(Net::HTTP.get(uri))
  response['text'][0]
end

if ARGV.length < 2
  puts "Too few arguments"
  exit
end

file_to_translate = ARGV[0]
result_file = ARGV[1]

doc = File.open(file_to_translate) { |f| Nokogiri::XML(f) }
paragraphs = doc.css('p')

iter_to = paragraphs.length - 1

(0..iter_to).each do |i|
  translated_p = Nokogiri::XML::Node.new 'p', doc
  emphasis_node = Nokogiri::XML::Node.new 'emphasis', doc
  translated_p.add_child emphasis_node
  empty_line = Nokogiri::XML::Node.new 'empty-line', doc
  emphasis_node.content = translate(paragraphs[i].content)
  paragraphs[i].add_next_sibling(empty_line)
  paragraphs[i].add_next_sibling(translated_p)
  p i * 100 / iter_to.to_f
end

File.write(result_file, doc.to_xml)
