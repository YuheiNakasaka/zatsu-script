#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'date'
require 'optparse'

GITHUB_API_URL = 'https://api.github.com/graphql'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} --org=ORG --user=USER --from=YYYY-MM-DD --to=YYYY-MM-DD"
  opts.on('--org=ORG', 'GitHub Organization名') { |v| options[:org] = v }
  opts.on('--user=USER', 'GitHubユーザー名') { |v| options[:user] = v }
  opts.on('--from=DATE', '開始日 (YYYY-MM-DD)') { |v| options[:from] = v }
  opts.on('--to=DATE', '終了日 (YYYY-MM-DD)') { |v| options[:to] = v }
  opts.on('--token=TOKEN', 'GitHub Personal Access Token') { |v| options[:token] = v }
end.parse!

[:org, :user, :from, :to].each do |k|
  unless options[k]
    puts "Missing option: --#{k}"
    exit 1
  end
end
token = options[:token] || ENV['GITHUB_TOKEN']
unless token
  puts 'GitHubトークンが必要です。--tokenオプションかGITHUB_TOKEN環境変数で指定してください。'
  exit 1
end

def run_github_graphql(query, variables, token)
  uri = URI(GITHUB_API_URL)
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type'] = 'application/json'
  req.body = { query:, variables: }.to_json
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "GitHub GraphQL error: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

# とりあえずローカルPCで実行することしか考えてないのでJSTになるはず
from_iso = Date.parse(options[:from]).to_time.iso8601
to_iso = (Date.parse(options[:to]) + 1).to_time.iso8601

query = <<~GRAPHQL
  query($user: String!, $from: DateTime!, $to: DateTime!) {
    user(login: $user) {
      contributionsCollection(from: $from, to: $to) {
        pullRequestContributions(first: 100) {
          nodes {
            pullRequest {
              title
              url
              createdAt
              additions
              deletions
              repository { nameWithOwner }
            }
          }
        }
        issueContributions(first: 100) {
          nodes {
            issue {
              title
              url
              createdAt
              repository { nameWithOwner }
            }
          }
        }
        pullRequestReviewContributions(first: 100) {
          nodes {
            pullRequest {
              title
              url
              repository { nameWithOwner }
            }
            occurredAt
          }
        }
      }
    }
  }
GRAPHQL

variables = {
  user: options[:user],
  from: from_iso,
  to: to_iso
}

res = run_github_graphql(query, variables, token)
if res['errors']
  puts 'GraphQL エラー:'
  puts JSON.pretty_generate(res['errors'])
  exit 1
end
cc = res.dig('data', 'user', 'contributionsCollection')

puts '# 作成したPR'
cc['pullRequestContributions']['nodes'].each do |n|
  pr = n['pullRequest']
  next unless pr['repository']['nameWithOwner'].start_with?("#{options[:org]}/")
  puts "- #{pr['createdAt']} #{pr['title']} #{pr['url']} (+#{pr['additions']}, -#{pr['deletions']})"
end

puts "\n# 作成したIssue"
cc['issueContributions']['nodes'].each do |n|
  issue = n['issue']
  next unless issue['repository']['nameWithOwner'].start_with?("#{options[:org]}/")
  puts "- #{issue['createdAt']} #{issue['title']} #{issue['url']}"
end

puts "\n# レビューしたPR"
cc['pullRequestReviewContributions']['nodes'].each do |n|
  pr = n['pullRequest']
  next unless pr['repository']['nameWithOwner'].start_with?("#{options[:org]}/")
  puts "- #{n['occurredAt']} #{pr['title']} #{pr['url']}"
end
