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
  opts.on('--user=USER', 'GitHubユーザー名(カンマ区切りで複数指定可)') { |v| options[:user] = v }
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

def fetch_all_reviews(query, variables, token, has_next_page = true, cursor = nil)
  all_nodes = []

  while has_next_page
    current_variables = variables.dup
    current_variables[:cursor] = cursor if cursor

    res = run_github_graphql(query, current_variables, token)
    if res['errors']
      puts 'GraphQL エラー:'
      puts JSON.pretty_generate(res['errors'])
      exit 1
    end

    contributions = res.dig('data', 'user', 'contributionsCollection', 'pullRequestReviewContributions')
    all_nodes += contributions['nodes']

    has_next_page = contributions.dig('pageInfo', 'hasNextPage')
    cursor = contributions.dig('pageInfo', 'endCursor')
  end

  all_nodes
end

# とりあえずローカルPCで実行することしか考えてないのでJSTになるはず
from_iso = Date.parse(options[:from]).to_time.iso8601
to_iso = (Date.parse(options[:to]) + 1).to_time.iso8601

query = <<~GRAPHQL
  query($user: String!, $from: DateTime!, $to: DateTime!, $cursor: String) {
    user(login: $user) {
      contributionsCollection(from: $from, to: $to) {
        pullRequestReviewContributions(first: 100, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            pullRequest {
              repository { nameWithOwner }
            }
            occurredAt
          }
        }
      }
    }
  }
GRAPHQL

results = {}
options[:user].split(',').each do |user|
  variables = {
    user:,
    from: from_iso,
    to: to_iso
  }

  all_reviews = fetch_all_reviews(query, variables, token)

  # 指定した組織のレビューのみをカウント
  org_reviews = all_reviews.select do |review|
    review['pullRequest']['repository']['nameWithOwner'].start_with?("#{options[:org]}/")
  end

  results[user] = org_reviews.count
end

# 結果を表示
puts "## レビュー数集計 (#{options[:from]} - #{options[:to]})"
puts "組織: #{options[:org]}"
puts ''
results.each do |user, count|
  puts "#{user}: #{count} reviews"
end

# 合計も表示
if results.size > 1
  total = results.values.sum
  puts ''
  puts "合計: #{total} reviews"
end
