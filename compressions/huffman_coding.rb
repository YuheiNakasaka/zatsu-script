class HuffmanNode
  attr_accessor :char, :freq, :left, :right

  def initialize(char = nil, freq = 0, left = nil, right = nil)
    @char = char
    @freq = freq
    @left = left
    @right = right
  end

  def leaf?
    left.nil? && right.nil?
  end
end

class HuffmanCoding
  def build_tree(text)
    freq = text.chars.tally
    nodes = freq.map { |char, f| HuffmanNode.new(char, f) }

    while nodes.size > 1
      nodes = nodes.sort_by(&:freq)
      left = nodes.shift
      right = nodes.shift
      merged = HuffmanNode.new(nil, left.freq + right.freq, left, right)
      nodes << merged
    end

    nodes.first
  end

  def build_codes(node, prefix = '', code_map = {})
    return code_map[node.char] = prefix if node.leaf?

    build_codes(node.left,  prefix + '0', code_map)
    build_codes(node.right, prefix + '1', code_map)
    code_map
  end

  def encode(text)
    tree = build_tree(text)
    codes = build_codes(tree)
    encoded = text.chars.map { |c| codes[c] }.join
    [encoded, tree]
  end

  def decode(bits, tree)
    result = ''
    node = tree
    bits.chars.each do |bit|
      node = bit == '0' ? node.left : node.right
      if node.leaf?
        result << node.char
        node = tree
      end
    end
    result
  end

  def print_tree(node, prefix = '', is_left = true)
    return if node.nil?
    print_tree(node.right, prefix + (is_left ? '│   ' : '    '), false)
    puts prefix + (is_left ? '└── ' : '┌── ') + (node.char ? "#{node.char}(#{node.freq})" : "* (#{node.freq})")
    print_tree(node.left, prefix + (is_left ? '    ' : '│   '), true)
  end

  def print_code_map(code_map)
    puts '符号割り当て:'
    code_map.each do |char, code|
      puts "  #{char.inspect}: #{code}"
    end
  end
end

# 使用例
text = 'AABACDABAA'
hc = HuffmanCoding.new
encoded, tree = hc.encode(text)
decoded = hc.decode(encoded, tree)
codes = hc.build_codes(tree)

puts "Original: #{text}"
puts "Encoded:  #{encoded}"
puts "Decoded:  #{decoded}"

puts "\n--- ハフマン木 ---"
hc.print_tree(tree)
puts "\n--- コードマップ ---"
hc.print_code_map(codes)
