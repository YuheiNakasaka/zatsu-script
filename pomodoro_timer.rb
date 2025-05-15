# frozen_string_literal: true

class PomodoroTimer
  def initialize(work_minutes: 25, break_minutes: 5, session_count: 4)
    @work_minutes = work_minutes
    @break_minutes = break_minutes
    @session_count = session_count
  end

  def start
    while @session_count > 0
      puts "Start! #{@session_count} sessions left"
      run_timer(@work_minutes, message: 'Work time is over!')
      run_timer(@break_minutes, message: 'Break time is over!')
      @session_count -= 1
    end
  end

  private

  def run_timer(minutes, message:)
    minutes.downto(1) do |i|
      print "#{i} minutes left\n"
      sleep 60
    end
    notify(message)
  end

  def notify(message)
    puts message
  end
end

# 使用例
timer = PomodoroTimer.new(session_count: 1)
timer.start
