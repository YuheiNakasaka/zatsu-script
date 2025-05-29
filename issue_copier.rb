#!/usr/bin/env ruby
require 'json'
require 'net/http'
require 'uri'
require 'optparse'

class GitHubIssueCopier
  GITHUB_API = 'https://api.github.com/graphql'
  REST_API = 'https://api.github.com'
  ISSUE_URL_REGEX = %r{github\.com/([^/]+)/([^/]+)/issues/(\d+)}i
  REPO_URL_REGEX = %r{github\.com/([^/]+)/([^/]+)}i
  LABELS_LIMIT = 10
  ASSIGNEES_LIMIT = 10
  PROJECTS_LIMIT = 10
  FIELDS_LIMIT = 20

  def initialize(source_issue_url:, target_repo_url:)
    @token = ENV['GITHUB_TOKEN']
    @source_owner, @source_repo, @source_issue_number = parse_issue_url(source_issue_url)
    @target_owner, @target_repo = parse_repo_url(target_repo_url)
  end

  def copy
    issue_data = fetch_issue_data
    new_issue = create_issue(issue_data)
    copy_labels(issue_data['labels']['nodes'], new_issue['number'])
    copy_assignees(issue_data['assignees']['nodes'], new_issue['number'])
    if issue_data['projectItems'] && issue_data['projectItems']['nodes']
      copy_projects(issue_data['projectItems']['nodes'], new_issue['id'])
    end
  end

  private

  def parse_issue_url(url)
    match = url.match(ISSUE_URL_REGEX)
    raise '不正なIssue URLです' unless match
    [match[1], match[2], match[3].to_i]
  end

  def parse_repo_url(url)
    match = url.match(REPO_URL_REGEX)
    raise '不正なリポジトリURLです' unless match
    [match[1], match[2]]
  end

  def fetch_issue_data
    query = <<~GRAPHQL
      query {
        repository(owner: "#{@source_owner}", name: "#{@source_repo}") {
          issue(number: #{@source_issue_number}) {
            title
            body
            id
            labels(first: #{LABELS_LIMIT}) { nodes { name } }
            assignees(first: #{ASSIGNEES_LIMIT}) { nodes { login } }
            projectItems(first: #{PROJECTS_LIMIT}) {
              nodes {
                id
                project {
                  title
                  fields(first: #{FIELDS_LIMIT}) {
                    nodes {
                      ... on ProjectV2FieldCommon {
                        id
                        name
                      }
                      ... on ProjectV2SingleSelectField {
                        id
                        name
                        options { id name }
                      }
                      ... on ProjectV2IterationField {
                        id
                        name
                        configuration { iterations { id startDate } }
                      }
                    }
                  }
                }
                fieldValues(first: #{FIELDS_LIMIT}) {
                  nodes {
                    ... on ProjectV2ItemFieldTextValue {
                      text
                      field { ... on ProjectV2FieldCommon { name } }
                    }
                    ... on ProjectV2ItemFieldDateValue {
                      date
                      field { ... on ProjectV2FieldCommon { name } }
                    }
                    ... on ProjectV2ItemFieldSingleSelectValue {
                      name
                      optionId
                      field { ... on ProjectV2FieldCommon { name } }
                    }
                    ... on ProjectV2ItemFieldNumberValue {
                      number
                      field { ... on ProjectV2FieldCommon { name } }
                    }
                    ... on ProjectV2ItemFieldIterationValue {
                      title
                      iterationId
                      field { ... on ProjectV2FieldCommon { name } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    res = post_graphql(query)
    unless res.dig('data', 'repository', 'issue')
      warn "GraphQLレスポンス: #{res.inspect}"
      raise 'GraphQLクエリでIssue情報が取得できませんでした。URLや権限、トークンを確認してください。'
    end
    res['data']['repository']['issue']
  end

  def create_issue(issue_data)
    uri = URI("#{REST_API}/repos/#{@target_owner}/#{@target_repo}/issues")
    res = post_rest(uri, {
      title: issue_data['title'],
      body: issue_data['body']
    })
    body = JSON.parse(res.body)
    body['id'] = get_issue_node_id(body['number'])
    body
  end

  def get_issue_node_id(issue_number)
    query = <<~GRAPHQL
      query {
        repository(owner: "#{@target_owner}", name: "#{@target_repo}") {
          issue(number: #{issue_number}) {
            id
          }
        }
      }
    GRAPHQL
    res = post_graphql(query)
    res['data']['repository']['issue']['id']
  end

  def copy_labels(labels, issue_number)
    label_names = labels.map { |l| l['name'] }
    return if label_names.empty?
    uri = URI("#{REST_API}/repos/#{@target_owner}/#{@target_repo}/issues/#{issue_number}/labels")
    post_rest(uri, { labels: label_names })
  end

  def copy_assignees(assignees, issue_number)
    logins = assignees.map { |a| a['login'] }
    return if logins.empty?
    uri = URI("#{REST_API}/repos/#{@target_owner}/#{@target_repo}/issues/#{issue_number}/assignees")
    post_rest(uri, { assignees: logins })
  end

  def copy_projects(project_items, new_issue_node_id)
    org_projects = fetch_org_projects(@target_owner)
    project_items.each do |item|
      project_title = item['project']['title']
      field_values = item['fieldValues']['nodes']
      target_project = org_projects.find { |p| p['title'] == project_title }
      next unless target_project
      target_fields = target_project['fields']['nodes']
      project_id = target_project['id']
      new_item_id = add_to_project(project_id, new_issue_node_id)
      field_values.each do |value|
        name = value.dig('field', 'name')
        target_field = target_fields.find { |f| f['name'] == name }
        target_field_id = target_field&.dig('id')
        next unless target_field_id
        if value['text']
          update_project_field(project_id, new_item_id, target_field_id, { text: value['text'] })
        elsif value['date']
          update_project_field(project_id, new_item_id, target_field_id, { date: value['date'] })
        elsif value['number']
          update_project_field(project_id, new_item_id, target_field_id, { number: value['number'] })
        elsif value['optionId']
          option_name = value['name']
          if target_field['options'] && option_name
            target_option = target_field['options'].find { |opt| opt['name'] == option_name }
            if target_option
              update_project_field(project_id, new_item_id, target_field_id, { singleSelectOptionId: target_option['id'] })
            end
          end
        elsif value['iterationId']
          update_project_field(project_id, new_item_id, target_field_id, { iterationId: value['iterationId'] })
        end
      end
    end
  end

  def fetch_org_projects(org)
    query = <<~GRAPHQL
      query {
        organization(login: "#{org}") {
          projectsV2(first: #{PROJECTS_LIMIT}) {
            nodes {
              id
              title
              fields(first: #{FIELDS_LIMIT}) {
                nodes {
                  ... on ProjectV2FieldCommon {
                    id
                    name
                  }
                  ... on ProjectV2SingleSelectField {
                    id
                    name
                    options { id name }
                  }
                  ... on ProjectV2IterationField {
                    id
                    name
                    configuration { iterations { id startDate } }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL
    res = post_graphql(query)
    res['data']['organization']['projectsV2']['nodes']
  end

  def add_to_project(project_id, content_id)
    mutation = <<~GRAPHQL
      mutation {
        addProjectV2ItemById(input: {
          projectId: "#{project_id}",
          contentId: "#{content_id}"
        }) {
          item { id }
        }
      }
    GRAPHQL
    res = post_graphql(mutation)
    res['data']['addProjectV2ItemById']['item']['id']
  end

  def update_project_field(project_id, item_id, field_id, value)
    value_str =
      if value[:text]
        "text: #{value[:text].to_json}"
      elsif value[:date]
        "date: #{value[:date].to_json}"
      elsif value[:number]
        "number: #{value[:number].to_json}"
      elsif value[:singleSelectOptionId]
        "singleSelectOptionId: #{value[:singleSelectOptionId].to_json}"
      elsif value[:iterationId]
        "iterationId: #{value[:iterationId].to_json}"
      else
        raise "未知の値タイプ: #{value.inspect}"
      end

    mutation = <<~GRAPHQL
      mutation {
        updateProjectV2ItemFieldValue(input: {
          projectId: \"#{project_id}\",
          itemId: \"#{item_id}\",
          fieldId: \"#{field_id}\",
          value: { #{value_str} }
        }) {
          projectV2Item { id }
        }
      }
    GRAPHQL
    res = post_graphql(mutation)
    unless res.dig('data', 'updateProjectV2ItemFieldValue')
      warn "フィールド更新失敗: #{res.inspect}"
    end
    res
  end

  def post_graphql(query)
    uri = URI(GITHUB_API)
    req = Net::HTTP::Post.new(uri)
    set_common_headers(req)
    req.body = { query: }.to_json
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "GitHub GraphQL error: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end

  def post_rest(uri, body_hash)
    req = Net::HTTP::Post.new(uri)
    set_common_headers(req)
    req.body = body_hash.to_json
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "REST APIエラー: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    res
  end

  def set_common_headers(req)
    req['Authorization'] = "Bearer #{@token}"
    req['Content-Type'] = 'application/json'
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: copy_issue.rb --source=ISSUE_URL --target=REPO_URL'
  opts.on('--source=URL', 'コピー元のIssueのURL') { |v| options[:source] = v }
  opts.on('--target=URL', 'コピー先リポジトリのURL') { |v| options[:target] = v }
end.parse!

copier = GitHubIssueCopier.new(
  source_issue_url: options[:source],
  target_repo_url: options[:target]
)
copier.copy
