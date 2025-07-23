#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'date'
require 'optparse'

GITHUB_API_URL = 'https://api.github.com/graphql'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} --org=ORG --repo=REPO --pr=PR_NUMBER [--token=TOKEN]"
  opts.on('--org=ORG', 'GitHub Organization名') { |v| options[:org] = v }
  opts.on('--repo=REPO', 'リポジトリ名') { |v| options[:repo] = v }
  opts.on('--pr=PR_NUMBER', 'PR番号') { |v| options[:pr] = v.to_i }
  opts.on('--token=TOKEN', 'GitHub Personal Access Token') { |v| options[:token] = v }
  opts.on('--format=FORMAT', '出力形式 (json|summary)', '詳細(json)または要約(summary)') { |v| options[:format] = v }
end.parse!

[:org, :repo, :pr].each do |k|
  unless options[k]
    puts "必須オプションが不足しています: --#{k}"
    exit 1
  end
end

token = options[:token] || ENV['GITHUB_TOKEN']
unless token
  puts 'GitHubトークンが必要です。--tokenオプションかGITHUB_TOKEN環境変数で指定してください。'
  exit 1
end

output_format = options[:format] || 'summary'

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

def fetch_paginated_data(query, variables, token, path_to_connection)
  all_nodes = []
  has_next_page = true
  cursor = nil

  while has_next_page
    current_variables = variables.dup
    current_variables[:cursor] = cursor if cursor

    res = run_github_graphql(query, current_variables, token)

    if res['errors']
      puts 'GraphQL エラー:'
      puts JSON.pretty_generate(res['errors'])
      exit 1
    end

    # パスを辿ってconnectionを取得
    connection = res['data']
    path_to_connection.each { |key| connection = connection[key] }

    all_nodes += connection['nodes']
    page_info = connection['pageInfo']
    has_next_page = page_info['hasNextPage']
    cursor = page_info['endCursor']
  end

  all_nodes
end

# PRの基本情報とコメントを取得するクエリ
pr_query = <<~GRAPHQL
  query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        title
        author { login }
        createdAt
        state
        url
        comments(first: 100, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            author { login }
            body
            createdAt
            updatedAt
            url
          }
        }
      }
    }
  }
GRAPHQL

# レビューコメントを取得するクエリ
review_query = <<~GRAPHQL
  query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviews(first: 100, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            author { login }
            body
            state
            createdAt
            updatedAt
            url
            comments(first: 100) {
              nodes {
                author { login }
                body
                createdAt
                updatedAt
                path
                line
                url
              }
            }
          }
        }
      }
    }
  }
GRAPHQL

variables = {
  owner: options[:org],
  repo: options[:repo],
  number: options[:pr]
}

# PRのDiscussionコメントを取得
puts "PR ##{options[:pr]} のコメントを取得中..."
discussion_comments = fetch_paginated_data(
  pr_query,
  variables,
  token,
  ['repository', 'pullRequest', 'comments']
)

# PRの基本情報も取得
pr_info_res = run_github_graphql(pr_query, variables, token)
pr_info = pr_info_res.dig('data', 'repository', 'pullRequest')

# レビューコメントを取得
review_comments = []
reviews = fetch_paginated_data(
  review_query,
  variables,
  token,
  ['repository', 'pullRequest', 'reviews']
)

reviews.each do |review|
  # レビューサマリーコメント
  if review['body'] && !review['body'].strip.empty?
    review_comments << {
      'type' => 'review_summary',
      'author' => review['author'],
      'body' => review['body'],
      'createdAt' => review['createdAt'],
      'updatedAt' => review['updatedAt'],
      'url' => review['url'],
      'state' => review['state']
    }
  end

  # 個別のレビューコメント
  review['comments']['nodes'].each do |comment|
    review_comments << {
      'type' => 'review_comment',
      'author' => comment['author'],
      'body' => comment['body'],
      'createdAt' => comment['createdAt'],
      'updatedAt' => comment['updatedAt'],
      'url' => comment['url'],
      'path' => comment['path'],
      'line' => comment['line']
    }
  end
end

# 結果を表示
if output_format == 'json'
  result = {
    'pr_info' => pr_info,
    'discussion_comments' => discussion_comments,
    'review_comments' => review_comments,
    'summary' => {
      'total_discussion_comments' => discussion_comments.length,
      'total_review_comments' => review_comments.length,
      'total_comments' => discussion_comments.length + review_comments.length
    }
  }
  puts JSON.pretty_generate(result)
else
  puts "\n" + '=' * 60
  puts "PR情報: #{pr_info['title']}"
  puts "作成者: #{pr_info['author']['login']}"
  puts "状態: #{pr_info['state']}"
  puts "URL: #{pr_info['url']}"
  puts "作成日: #{pr_info['createdAt']}"
  puts '=' * 60

  puts "\n📝 Discussion コメント数: #{discussion_comments.length}"
  discussion_comments.each_with_index do |comment, index|
    puts "\n--- Discussion コメント ##{index + 1} ---"
    puts "作成者: #{comment['author']['login']}"
    puts "作成日: #{comment['createdAt']}"
    puts "内容: #{comment['body'][0..200]}#{'...' if comment['body'].length > 200}"
    puts "URL: #{comment['url']}"
  end

  puts "\n🔍 Review コメント数: #{review_comments.length}"
  review_comments.each_with_index do |comment, index|
    puts "\n--- Review コメント ##{index + 1} ---"
    puts "タイプ: #{comment['type']}"
    puts "作成者: #{comment['author']['login']}"
    puts "作成日: #{comment['createdAt']}"
    if comment['path']
      puts "ファイル: #{comment['path']}:#{comment['line']}"
    end
    if comment['state']
      puts "レビュー状態: #{comment['state']}"
    end
    puts "内容: #{comment['body'][0..200]}#{'...' if comment['body'].length > 200}"
    puts "URL: #{comment['url']}"
  end

  puts "\n" + '=' * 60
  puts '📊 合計'
  puts "Discussion コメント: #{discussion_comments.length}"
  puts "Review コメント: #{review_comments.length}"
  puts "総コメント数: #{discussion_comments.length + review_comments.length}"
  puts '=' * 60
end
