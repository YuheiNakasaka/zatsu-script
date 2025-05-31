# frozen_string_literal: true

require 'socket'
require 'dotenv'
Dotenv.load

class Solver
  # 想定するproblem_textの例
  #
  # Time Limit: 22s
  # Q. 5/15
  # x^28=13885623290331993173611514953677505679054455986964592442333661951346875572706397735446048417830011570840695823174814949921
  # x=?
  def run(problem_text)
    if problem_text.match(/x\^(\d+)\s*=\s*(\d+)/)
      exponent = $1.to_i
      value = $2.to_i
      nth_root(value, exponent)
    else
      1
    end
  rescue
    1
  end

  private

  def nth_root(value, n)
    return 1 if value <= 1
    return value if n == 1

    # 対数を使った高速計算
    begin
      log10_value = Math.log10(value)
      log10_result = log10_value / n
      result = (10 ** log10_result).round

      # ±1の範囲で最適化
      best_candidate = result
      best_error = calculate_error(result, n, value)

      [result - 1, result + 1].each do |candidate|
        next if candidate <= 0
        error = calculate_error(candidate, n, value)
        if error < best_error
          best_error = error
          best_candidate = candidate
        end
      end

      best_candidate
    rescue
      # フォールバック: 桁数による推定
      digits = value.to_s.length
      (10 ** (digits.to_f / n)).round
    end
  end

  def calculate_error(candidate, n, target_value)
    begin
      calculated_value = candidate ** n
      (calculated_value - target_value).abs
    rescue
      Float::INFINITY
    end
  end
end

class TbcQuest
  def solve
    puts 'Start solving...'
    host = ENV['TBCQ_HOST']
    port = ENV['TBCQ_PORT']

    puts "Connecting to #{host}:#{port}..."
    socket = TCPSocket.new(host, port)
    solver = Solver.new

    15.times do |i|
      puts "#{i + 1}/15"

      response = read_response(socket)
      puts response[0..200] + (response.length > 200 ? '...' : '')

      if response.include?('Wrong answer')
        puts 'Wrong answer'
        break
      end

      answer = solver.run(response)
      puts "Answer: #{answer}"

      socket.puts(answer)
      socket.flush
    end
    final_result = read_response(socket)

    socket.close
    final_result
  end

  private

  def read_response(socket)
    response = ''
    while line = socket.gets
      response += line
      # 雑に読み込む
      break if line.include?('x=?') || response.length > 2**24
    end
    response.strip
  end
end

if ENV['TEST'] == 'true'
  require 'minitest/autorun'

  class SolverTest < Minitest::Test
    def test_1st_root
      question = 'x^1=1'
      solver = Solver.new
      assert_equal 1, solver.run(question)
    end

    def test_28th_root
      question = 'x^28=13885623290331993173611514953677505679054455986964592442333661951346875572706397735446048417830011570840695823174814949921'
      solver = Solver.new
      assert_equal 21209, solver.run(question)
    end
  end
else
  begin
    quest = TbcQuest.new
    result = quest.solve
    puts "Final result: #{result}"
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace
  end
end
