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

resp = encode('a'*1 + 'b'*10 + 'c'*100 + 'a'*10)
puts resp
puts decode(resp)
