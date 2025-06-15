#! /usr/bin/env ruby

def encode(str)
  cur = ''
  count = 0
  result = ''
  str.each_char do |char|
    if char != cur
      if cur != ''
        result = "#{result}#{count}#{cur}"
      end
      count = 1
      cur = char
    else
      count += 1
    end
  end
  "#{result}#{count}#{cur}"
end

def decode(encoded_str)
  return '' if encoded_str.empty?

  result = ''
  encoded_str.scan(/(\d+)(\w)/).each do |count, char|
    result = "#{result}#{char * count.to_i}"
  end
  result
end

original = 'a'*1 + 'b'*10 + 'c'*100 + 'a'*10
resp = encode(original)
puts "Original: #{original}"
puts "Encoded:  #{resp}"
puts "Decoded:  #{decode(resp)}"

# GPT生成の参考実装
# `chunk(&:itself)`というメソッドは知らないかった。隣り合う同じ文字ごとにグループ化するので⇩みたいになる。
# Run Length Encodingを作るためのメソッドにしか見えん...
# [
#   ["A", ["A", "A", "A"]],
#   ["B", ["B", "B", "B"]],
#   ["C", ["C", "C"]],
#   ["D", ["D"]],
#   ["A", ["A", "A"]]
# ]
class RunLengthEncoding
  def self.encode(input)
    input.chars.chunk(&:itself).map { |char, group| "#{char}#{group.length}" }.join
  end

  def self.decode(input)
    input.scan(/(\D)(\d+)/).map { |char, count| char * count.to_i }.join
  end
end

# 使用例
original = 'AAABBBCCDAA'
encoded  = RunLengthEncoding.encode(original)
decoded  = RunLengthEncoding.decode(encoded)

puts "Original: #{original}"  # => AAABBBCCDAA
puts "Encoded:  #{encoded}"   # => A3B3C2D1A2
puts "Decoded:  #{decoded}"   # => AAABBBCCDAA
