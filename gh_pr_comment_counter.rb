#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'date'
require 'optparse'

GITHUB_API_URL = 'https://api.github.com/graphql'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} --org=ORG --repo=REPO --user=USER --from=YYYY-MM-DD --to=YYYY-MM-DD [--token=TOKEN]"
  opts.on('--org=ORG', 'GitHub Organization名') { |v| options[:org] = v }
  opts.on('--repo=REPO', 'リポジトリ名') { |v| options[:repo] = v }
  opts.on('--user=USER', 'GitHubユーザー名(カンマ区切りで複数指定可)') { |v| options[:user] = v }
  opts.on('--from=DATE', '開始日 (YYYY-MM-DD)') { |v| options[:from] = v }
  opts.on('--to=DATE', '終了日 (YYYY-MM-DD)') { |v| options[:to] = v }
  opts.on('--token=TOKEN', 'GitHub Personal Access Token') { |v| options[:token] = v }
  opts.on('--format=FORMAT', '出力形式 (summary|details)', 'summary: 集計のみ, details: 詳細情報も表示') { |v| options[:format] = v }
end.parse!

[:org, :repo, :user, :from, :to].each do |k|
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

# 指定期間内のPRを取得するクエリ
pr_list_query = <<~GRAPHQL
  query($owner: String!, $repo: String!, $cursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequests(first: 100, after: $cursor, orderBy: {field: UPDATED_AT, direction: DESC}) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          number
          title
          author { login }
          createdAt
          updatedAt
          state
          url
        }
      }
    }
  }
GRAPHQL

# PRのコメントを取得するクエリ
pr_comments_query = <<~GRAPHQL
  query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
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
review_comments_query = <<~GRAPHQL
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

from_date = Date.parse(options[:from])
to_date = Date.parse(options[:to])
target_users = options[:user].split(',').map(&:strip)

variables = {
  owner: options[:org],
  repo: options[:repo]
}

puts "#{options[:org]}/#{options[:repo]} のPRを取得中..."

# 全PRを取得
all_prs = fetch_paginated_data(
  pr_list_query,
  variables,
  token,
  ['repository', 'pullRequests']
)

# 期間内のPRをフィルタリング
period_prs = all_prs.select do |pr|
  pr_date = Date.parse(pr['updatedAt'])
  pr_date >= from_date && pr_date <= to_date
end

puts "期間内のPR数: #{period_prs.length}"

# 各ユーザーのコメント数を集計
user_comment_counts = {}
target_users.each { |user| user_comment_counts[user] = { discussion: 0, review_summary: 0, review_comment: 0, total: 0, details: [] } }

period_prs.each_with_index do |pr, index|
  puts "PR ##{pr['number']} のコメントを取得中... (#{index + 1}/#{period_prs.length})" if index % 10 == 0

  pr_variables = variables.dup
  pr_variables[:number] = pr['number']

  # Discussion コメントを取得
  discussion_comments = fetch_paginated_data(
    pr_comments_query,
    pr_variables,
    token,
    ['repository', 'pullRequest', 'comments']
  )

  # Review コメントを取得
  reviews = fetch_paginated_data(
    review_comments_query,
    pr_variables,
    token,
    ['repository', 'pullRequest', 'reviews']
  )

  # Discussion コメントをカウント
  discussion_comments.each do |comment|
    author = comment['author']['login']
    if target_users.include?(author)
      comment_date = Date.parse(comment['createdAt'])
      if comment_date >= from_date && comment_date <= to_date
        user_comment_counts[author][:discussion] += 1
        user_comment_counts[author][:total] += 1
        if output_format == 'details'
          user_comment_counts[author][:details] << {
            type: 'discussion',
            pr_number: pr['number'],
            pr_title: pr['title'],
            created_at: comment['createdAt'],
            url: comment['url']
          }
        end
      end
    end
  end

  # Review コメントをカウント
  reviews.each do |review|
    # レビューサマリーコメント
    if review['body'] && !review['body'].strip.empty? && review['author']
      author = review['author']['login']
      if target_users.include?(author)
        comment_date = Date.parse(review['createdAt'])
        if comment_date >= from_date && comment_date <= to_date
          user_comment_counts[author][:review_summary] += 1
          user_comment_counts[author][:total] += 1
          if output_format == 'details'
            user_comment_counts[author][:details] << {
              type: 'review_summary',
              pr_number: pr['number'],
              pr_title: pr['title'],
              created_at: review['createdAt'],
              url: review['url']
            }
          end
        end
      end
    end

    # 個別のレビューコメント
    review['comments']['nodes'].each do |comment|
      author = comment['author']['login']
      if target_users.include?(author)
        comment_date = Date.parse(comment['createdAt'])
        if comment_date >= from_date && comment_date <= to_date
          user_comment_counts[author][:review_comment] += 1
          user_comment_counts[author][:total] += 1
          if output_format == 'details'
            user_comment_counts[author][:details] << {
              type: 'review_comment',
              pr_number: pr['number'],
              pr_title: pr['title'],
              path: comment['path'],
              line: comment['line'],
              created_at: comment['createdAt'],
              url: comment['url']
            }
          end
        end
      end
    end
  end
end

# 結果を表示
puts "\n" + '=' * 60
puts "PRコメント数集計 (#{options[:from]} - #{options[:to]})"
puts "リポジトリ: #{options[:org]}/#{options[:repo]}"
puts "対象PR数: #{period_prs.length}"
puts '=' * 60

user_comment_counts.each do |user, counts|
  puts "\n👤 #{user}:"
  puts "  Discussion コメント: #{counts[:discussion]}"
  puts "  Review サマリー: #{counts[:review_summary]}"
  puts "  Review コメント: #{counts[:review_comment]}"
  puts "  合計: #{counts[:total]}"

  if output_format == 'details' && !counts[:details].empty?
    puts "\n  📝 詳細:"
    counts[:details].sort_by { |d| d[:created_at] }.each_with_index do |detail, index|
      puts "    #{index + 1}. [#{detail[:type]}] PR ##{detail[:pr_number]}: #{detail[:pr_title][0..50]}#{'...' if detail[:pr_title].length > 50}"
      puts "       作成日: #{detail[:created_at]}"
      puts "       ファイル: #{detail[:path]}:#{detail[:line]}" if detail[:path]
      puts "       URL: #{detail[:url]}"
      puts ''
    end
  end
end

# 合計
if target_users.length > 1
  total_counts = {
    discussion: user_comment_counts.values.sum { |c| c[:discussion] },
    review_summary: user_comment_counts.values.sum { |c| c[:review_summary] },
    review_comment: user_comment_counts.values.sum { |c| c[:review_comment] },
    total: user_comment_counts.values.sum { |c| c[:total] }
  }

  puts "\n" + '=' * 60
  puts '📊 全体合計:'
  puts "  Discussion コメント: #{total_counts[:discussion]}"
  puts "  Review サマリー: #{total_counts[:review_summary]}"
  puts "  Review コメント: #{total_counts[:review_comment]}"
  puts "  総コメント数: #{total_counts[:total]}"
end

puts '=' * 60
