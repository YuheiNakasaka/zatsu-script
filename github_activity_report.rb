#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'date'
require 'time'
require 'optparse'

# GitHubの活動レポートを生成するクラス
class GitHubActivityReport
  attr_reader :token, :organization, :username, :date, :repos, :report_data

  BASE_API_URL = 'https://api.github.com'
  GRAPHQL_API_URL = 'https://api.github.com/graphql'

  def initialize(options = {})
    @token = options[:token] || ENV['GITHUB_TOKEN']
    @organization = options[:organization] || 'github'
    @username = options[:username] || get_authenticated_username
    @date = options[:date] || Date.today
    @repos = []
    @report_data = {
      commits: [],
      pull_requests: {
        created: [],
        reviewed: [],
        merged: []
      },
      issues: {
        created: [],
        commented: [],
        closed: []
      },
      repositories: [],
      contributions_count: {
        commits: 0,
        pull_requests: 0,
        issues: 0,
        reviews: 0
      }
    }

    validate_token!
  end

  def generate_report
    puts "🔍 #{@date.strftime('%Y-%m-%d')}の活動レポートを生成しています..."

    fetch_organization_repos
    fetch_user_contributions

    generate_report_output
  end

  private

  def validate_token!
    if @token.nil? || @token.empty?
      puts 'エラー: GITHUB_TOKENが設定されていません。'
      puts '環境変数にGITHUB_TOKENを設定するか、--tokenオプションで指定してください。'
      exit 1
    end
  end

  def get_authenticated_username
    response = make_rest_request('/user')
    response['login']
  end

  def fetch_organization_repos
    puts "📚 #{@organization}のリポジトリを取得しています..."

    page = 1
    per_page = 100
    all_repos = []

    loop do
      repos_response = make_rest_request("/orgs/#{@organization}/repos", { page:, per_page: })
      break if repos_response.empty?

      all_repos.concat(repos_response)
      page += 1
    end

    @repos = all_repos.map { |repo| repo['name'] }
    @report_data[:repositories] = @repos

    puts "✅ #{@repos.size}個のリポジトリを取得しました"
  end

  def fetch_user_contributions
    puts "🔄 ユーザー #{@username} の貢献情報を取得しています..."

    # GraphQLを使用して1日の活動をまとめて取得
    query = <<~GRAPHQL
      query($username: String!, $from: DateTime!, $to: DateTime!) {
        user(login: $username) {
          contributionsCollection(from: $from, to: $to) {
            commitContributionsByRepository {
              repository {
                name
                owner {
                  login
                }
              }
              contributions(first: 100) {
                totalCount
                nodes {
                  commitCount
                  occurredAt
                }
              }
            }
            pullRequestContributionsByRepository {
              repository {
                name
                owner {
                  login
                }
              }
              contributions(first: 100) {
                totalCount
                nodes {
                  pullRequest {
                    title
                    url
                    state
                    createdAt
                    merged
                    mergedAt
                    repository {
                      name
                    }
                  }
                }
              }
            }
            issueContributionsByRepository {
              repository {
                name
                owner {
                  login
                }
              }
              contributions(first: 100) {
                totalCount
                nodes {
                  issue {
                    title
                    url
                    state
                    createdAt
                    closedAt
                    repository {
                      name
                    }
                  }
                }
              }
            }
            pullRequestReviewContributionsByRepository {
              repository {
                name
                owner {
                  login
                }
              }
              contributions(first: 100) {
                totalCount
                nodes {
                  pullRequestReview {
                    state
                    createdAt
                    pullRequest {
                      title
                      url
                      repository {
                        name
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    # 日付範囲を設定（当日の0時から23時59分59秒まで）
    from_date = Time.new(@date.year, @date.month, @date.day, 0, 0, 0).iso8601
    to_date = Time.new(@date.year, @date.month, @date.day, 23, 59, 59).iso8601

    variables = {
      username: @username,
      from: from_date,
      to: to_date
    }

    response = make_graphql_request(query, variables)

    if response && response['data'] && response['data']['user']
      process_contributions(response['data']['user']['contributionsCollection'])
    else
      puts '⚠️ ユーザーの貢献情報を取得できませんでした'
    end
  end

  def process_contributions(contributions)
    # コミット情報の処理
    if contributions['commitContributionsByRepository']
      contributions['commitContributionsByRepository'].each do |repo_contribution|
        repo_name = repo_contribution['repository']['name']
        owner_login = repo_contribution['repository']['owner']['login']

        # 指定されたorganizationのリポジトリのみを対象とする
        next unless owner_login.downcase == @organization.downcase

        total_count = repo_contribution['contributions']['totalCount']
        @report_data[:contributions_count][:commits] += total_count

        if total_count > 0
          @report_data[:commits] << {
            repository: repo_name,
            count: total_count
          }
        end
      end
    end

    # PRの処理
    if contributions['pullRequestContributionsByRepository']
      contributions['pullRequestContributionsByRepository'].each do |repo_contribution|
        owner_login = repo_contribution['repository']['owner']['login']
        next unless owner_login.downcase == @organization.downcase

        repo_contribution['contributions']['nodes'].each do |node|
          pr = node['pullRequest']
          created_at = Time.parse(pr['createdAt']).to_date

          if created_at == @date
            @report_data[:pull_requests][:created] << {
              title: pr['title'],
              url: pr['url'],
              repository: pr['repository']['name'],
              state: pr['state']
            }
            @report_data[:contributions_count][:pull_requests] += 1
          end

          if pr['merged'] && Time.parse(pr['mergedAt']).to_date == @date
            @report_data[:pull_requests][:merged] << {
              title: pr['title'],
              url: pr['url'],
              repository: pr['repository']['name']
            }
          end
        end
      end
    end

    # Issueの処理
    if contributions['issueContributionsByRepository']
      contributions['issueContributionsByRepository'].each do |repo_contribution|
        owner_login = repo_contribution['repository']['owner']['login']
        next unless owner_login.downcase == @organization.downcase

        repo_contribution['contributions']['nodes'].each do |node|
          issue = node['issue']
          created_at = Time.parse(issue['createdAt']).to_date

          if created_at == @date
            @report_data[:issues][:created] << {
              title: issue['title'],
              url: issue['url'],
              repository: issue['repository']['name'],
              state: issue['state']
            }
            @report_data[:contributions_count][:issues] += 1
          end

          if issue['state'] == 'CLOSED' && issue['closedAt'] && Time.parse(issue['closedAt']).to_date == @date
            @report_data[:issues][:closed] << {
              title: issue['title'],
              url: issue['url'],
              repository: issue['repository']['name']
            }
          end
        end
      end
    end

    # PRレビューの処理
    if contributions['pullRequestReviewContributionsByRepository']
      contributions['pullRequestReviewContributionsByRepository'].each do |repo_contribution|
        owner_login = repo_contribution['repository']['owner']['login']
        next unless owner_login.downcase == @organization.downcase

        repo_contribution['contributions']['nodes'].each do |node|
          review = node['pullRequestReview']
          created_at = Time.parse(review['createdAt']).to_date

          if created_at == @date
            @report_data[:pull_requests][:reviewed] << {
              title: review['pullRequest']['title'],
              url: review['pullRequest']['url'],
              repository: review['pullRequest']['repository']['name'],
              state: review['state']
            }
            @report_data[:contributions_count][:reviews] += 1
          end
        end
      end
    end
  end

  def fetch_additional_activity
    # REST APIを使用して追加の活動情報を取得
    # コメントやその他の活動を取得する場合はここに実装
    # 例: リポジトリごとのコミット詳細情報など

    # 今回は基本的な情報はGraphQLで取得しているため、
    # 必要に応じてここに追加の情報取得処理を実装
  end

  def generate_report_output
    date_str = @date.strftime('%Y年%m月%d日')

    report = <<~REPORT
      # #{date_str} 活動レポート

      ## 📊 サマリー

      - 👤 ユーザー: #{@username}
      - 🏢 組織: #{@organization}
      - 📅 日付: #{date_str}

      ### 貢献数

      - コミット: #{@report_data[:contributions_count][:commits]}
      - プルリクエスト: #{@report_data[:contributions_count][:pull_requests]}
      - Issue: #{@report_data[:contributions_count][:issues]}
      - レビュー: #{@report_data[:contributions_count][:reviews]}

      ## 📝 詳細

    REPORT

    # コミット情報
    unless @report_data[:commits].empty?
      report += "### 🔨 コミット\n\n"
      @report_data[:commits].each do |commit|
        report += "- **#{commit[:repository]}**: #{commit[:count]}件のコミット\n"
      end
      report += "\n"
    end

    # プルリクエスト情報
    unless @report_data[:pull_requests][:created].empty?
      report += "### 🔀 作成したプルリクエスト\n\n"
      @report_data[:pull_requests][:created].each do |pr|
        state_emoji = pr[:state] == 'MERGED' ? '🟢' : (pr[:state] == 'CLOSED' ? '🔴' : '🟡')
        report += "- #{state_emoji} [#{pr[:title]}](#{pr[:url]}) (#{pr[:repository]})\n"
      end
      report += "\n"
    end

    unless @report_data[:pull_requests][:reviewed].empty?
      report += "### 👀 レビューしたプルリクエスト\n\n"
      @report_data[:pull_requests][:reviewed].each do |pr|
        state_emoji = pr[:state] == 'APPROVED' ? '✅' : (pr[:state] == 'CHANGES_REQUESTED' ? '🔄' : '💬')
        report += "- #{state_emoji} [#{pr[:title]}](#{pr[:url]}) (#{pr[:repository]})\n"
      end
      report += "\n"
    end

    unless @report_data[:pull_requests][:merged].empty?
      report += "### 🎯 マージされたプルリクエスト\n\n"
      @report_data[:pull_requests][:merged].each do |pr|
        report += "- 🟢 [#{pr[:title]}](#{pr[:url]}) (#{pr[:repository]})\n"
      end
      report += "\n"
    end

    # Issue情報
    unless @report_data[:issues][:created].empty?
      report += "### 🐛 作成したIssue\n\n"
      @report_data[:issues][:created].each do |issue|
        state_emoji = issue[:state] == 'CLOSED' ? '✅' : '📝'
        report += "- #{state_emoji} [#{issue[:title]}](#{issue[:url]}) (#{issue[:repository]})\n"
      end
      report += "\n"
    end

    unless @report_data[:issues][:closed].empty?
      report += "### 🎉 クローズしたIssue\n\n"
      @report_data[:issues][:closed].each do |issue|
        report += "- ✅ [#{issue[:title]}](#{issue[:url]}) (#{issue[:repository]})\n"
      end
      report += "\n"
    end

    # 活動がない場合のメッセージ
    if @report_data[:contributions_count].values.sum.zero?
      report += "### 📭 本日の活動はありません\n\n"
      report += "#{date_str}の#{@organization}組織内での活動は記録されていません。\n\n"
    end

    # レポート終了
    report += "---\n"
    report += "_このレポートは#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}に自動生成されました_\n"

    puts "\n#{report}"

    # ファイルに保存
    filename = "activity_report_#{@date.strftime('%Y%m%d')}.md"
    File.write(filename, report)
    puts "\n✅ レポートを #{filename} に保存しました"

    report
  end

  def make_rest_request(endpoint, params = {})
    uri = URI.parse("#{BASE_API_URL}#{endpoint}")

    # クエリパラメータがある場合は追加
    unless params.empty?
      uri.query = URI.encode_www_form(params)
    end

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "token #{@token}"
    request['Accept'] = 'application/vnd.github.v3+json'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == '200'
      JSON.parse(response.body)
    else
      puts "エラー: REST API リクエストが失敗しました (#{response.code})"
      puts "エンドポイント: #{endpoint}"
      puts "レスポンス: #{response.body}"
      {}
    end
  end

  def make_graphql_request(query, variables = {})
    uri = URI.parse(GRAPHQL_API_URL)
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = { query:, variables: }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == '200'
      result = JSON.parse(response.body)
      if result['errors']
        puts 'GraphQLエラー:'
        result['errors'].each do |error|
          puts "- #{error['message']}"
        end
      end
      result
    else
      puts "エラー: GraphQL APIリクエストが失敗しました (#{response.code})"
      puts "レスポンス: #{response.body}"
      {}
    end
  end
end

# コマンドラインオプションの処理
options = {}
OptionParser.new do |opts|
  opts.banner = "使用方法: #{$PROGRAM_NAME} [options]"

  opts.on('-t', '--token TOKEN', 'GitHub APIトークン (環境変数 GITHUB_TOKEN でも設定可能)') do |token|
    options[:token] = token
  end

  opts.on('-o', '--organization ORG', 'GitHub Organization名 (デフォルト: ga-tech)') do |org|
    options[:organization] = org
  end

  opts.on('-u', '--username USER', 'GitHubユーザー名 (指定しない場合は認証ユーザー)') do |user|
    options[:username] = user
  end

  opts.on('-d', '--date DATE', 'レポート対象日 (YYYY-MM-DD形式、デフォルト: 今日)') do |date|
    options[:date] = Date.parse(date)
  end

  opts.on('-h', '--help', 'ヘルプメッセージを表示') do
    puts opts
    exit
  end
end.parse!

# レポート生成の実行
report = GitHubActivityReport.new(options)
report.generate_report
