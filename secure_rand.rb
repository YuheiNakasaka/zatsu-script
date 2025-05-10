require 'openssl'

len = gets.chomp.to_i

def generate_secure_password(length = 16)
  chars = ('a'..'z').to_a +
          ('A'..'Z').to_a +
          ('0'..'9').to_a +
          ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+']
  password = Array.new(length) { chars[OpenSSL::Random.random_bytes(1).unpack('C').first % chars.size] }.join
  password[rand(length)] = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+'].sample

  password
end

puts generate_secure_password(32)
