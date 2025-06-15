nums = <<~NUM
123
456

678
901
234
567

890
123
456

789
12
345
678
NUM

p nums.split("\n").chunk{|line| line != '' || nil }.map {|_, group| group.map(&:to_i).sum }.sort.last
