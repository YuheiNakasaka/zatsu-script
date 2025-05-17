input = gets.chomp.to_i

roma_arr = [
  [1000, "M"],
  [500, "D"],
  [100, "C"],
  [50, "L"],
  [10, "X"],
  [5, "V"],
  [1, "I"],
]

ans = ''
loop do
  roma_arr.each do |num, roma|
    if input >= num
      ans += roma
      input -= num
      break
    end
  end

  break if input == 0
end

puts ans
