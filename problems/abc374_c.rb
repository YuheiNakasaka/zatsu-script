N = gets.to_i
K = gets.split.map(&:to_i)
a_sum = K.sum

ans = 10**18
(2 ** N).times do |i|
  b_sum = 0
  N.times do |j|
    if (i & (1 << j)) != 0
      b_sum += K[j]
    end
  end
  a = a_sum - b_sum
  b = b_sum > a ? b_sum : a
  ans = ans > b ? b : ans
end

puts ans
