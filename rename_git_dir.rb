#! /usr/bin/env ruby

require 'fileutils'

# ./skuld/.git_disabled
# ./ownr_api_client/.git_disabled
# ./tech_building/.git_disabled
# ./renosy_account_server/.git_disabled
# ./verdandi/.git_disabled
# ./renosy_asset/.git_disabled
# ./acme/ScrapScripts/.git_disabled
# ./acme/irb/.git_disabled
# ./acme/ai-sandbox/sprint-calendar/.git_disabled
# ./acme/ai-sandbox/mhn-leaderboard/.git_disabled
# ./acme/ai-sandbox/hatebu-podcast-deno/.git_disabled
# ./acme/ai-sandbox/hatebu-audio/.git_disabled
# ./acme/ai-sandbox/ailab/.git_disabled
# ./acme/ai-sandbox/project-rules/.git_disabled
# ./acme/ai-sandbox/mcp_ruby_sdk/.git_disabled
# ./acme/ai-sandbox/mcp_servers/arithmetic-server/.git_disabled
# ./acme/ai-sandbox/typescript-sdk/.git_disabled
# ./acme/ai-sandbox/mcp-from-scratch-with-clinerules/scrapbox-mcp/.git_disabled
# ./acme/rails8-sandbox/.git_disabled
# ./acme/json/.git_disabled
# ./acme/camp_web/.git_disabled
# ./acme/camp_web/.bundle/ruby/3.2.0/bundler/gems/devise-two-factor-87036f3b2e3c/.git_disabled
# ./acme/camp_web/.ruby-lsp/.bundle/ruby/3.2.0/bundler/gems/devise-two-factor-87036f3b2e3c/.git_disabled
# ./acme/gialog-diary/.git_disabled
# ./renosy_android_insight/.git_disabled
# ./eldir/.git_disabled
# ./ownr_app_mock/.git_disabled
# ./flow_by_renosy/.git_disabled
# ./ownr_server/.git_disabled
# ./renosy_magazine_cms/.git_disabled
# ./renosy_form/.git_disabled
# ./supplier-article/.git_disabled
# ./tech_after/.git_disabled
# ./rails/.git_disabled

Dir.glob('**/.*').each do |path|
  if File.directory?(path)
    if path.include?('.git_disabled')
      puts path
      File.rename(path, path.gsub('.git_disabled', '.git'))
    end
  end
end
