#!/usr/bin/env python3

# License: MIT

import argparse
import re
import sys

parser = argparse.ArgumentParser(description='merge')
parser.add_argument('files', metavar='file', nargs='+', help='zsh extended history files')
args = parser.parse_args()

p = re.compile(b':([ 0-9]*):([0-9]+);(.*)', re.S)
def get_lines(fp):
        histories = set()
        i = iter(fp.readlines())
        for line in i:
                date, time, command = p.match(line).groups()
                date = int(date)

                while len(command)>1 and command[-2] == b'\\'[0]:
                        command += next(i)
                histories.add((date, time, command))
        return histories

histories = set()
for f in args.files:
        with open(f, 'rb') as fp:
                histories.update(get_lines(fp))

for date,time,command in sorted(histories, key=lambda r: r[0]):
        print(":{:11}:".format(date), end="")
        sys.stdout.flush()
        sys.stdout.buffer.write(time)
        sys.stdout.buffer.write(';')
        sys.stdout.buffer.write(command)


