#! /usr/bin/env ruby

def pascal_triangle(n)
  result = []
  1.upto(n) do |i|
    if i == 1
      result << [1]
      next
    elsif i == 2
      result << [1, 1]
      next
    end

    result[i - 1] = []
    result[i - 1].unshift(1)
    (i - 2).times do |j|
      result[i - 1] << result[i - 2][j] + result[i - 2][j + 1]
    end
    result[i - 1].push(1)
  end
  result
end

def print_pascal_triangle(triangle)
  n = triangle.last.length
  l = n + (n - 1)
  pad = (l - 1) / 2
  1.upto(n) do |i|
    left = ' ' * (pad - i + 1)
    puts "#{left}#{triangle[i - 1].join(' ')}"
  end
end

if __FILE__ == $0
  require 'minitest/autorun'

  class PascalTriangleTest < Minitest::Test
    def test_one_row
      assert_equal [[1]], pascal_triangle(1)
    end

    def test_two_rows
      assert_equal [[1], [1, 1]], pascal_triangle(2)
    end


    def test_three_rows
      assert_equal [[1], [1, 1], [1, 2, 1]], pascal_triangle(3)
    end

    def test_ten_rows
      assert_equal [[1], [1, 1], [1, 2, 1], [1, 3, 3, 1], [1, 4, 6, 4, 1], [1, 5, 10, 10, 5, 1], [1, 6, 15, 20, 15, 6, 1], [1, 7, 21, 35, 35, 21, 7, 1], [1, 8, 28, 56, 70, 56, 28, 8, 1], [1, 9, 36, 84, 126, 126, 84, 36, 9, 1]], pascal_triangle(10)
    end
  end
else
  print_pascal_triangle(pascal_triangle(10))
end
