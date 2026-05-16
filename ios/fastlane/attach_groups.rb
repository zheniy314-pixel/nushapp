#!/usr/bin/env ruby
require "spaceship"

key_id    = ENV["APP_STORE_CONNECT_KEY_ID"]
issuer_id = ENV["APP_STORE_CONNECT_ISSUER_ID"]
key_path  = ENV["APP_STORE_CONNECT_KEY_PATH"]

unless key_id && issuer_id && key_path && File.exist?(key_path)
  abort "Set APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_PATH"
end

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: key_id,
  issuer_id: issuer_id,
  filepath: key_path
)

app_bundle   = ARGV[0] || "com.calc.domeClient"
version_num  = ARGV[1] || "2210"
group_names  = (ARGV[2] || "Go+++ Testers,Go+++ Testers 2").split(",").map(&:strip)

app = Spaceship::ConnectAPI::App.find(app_bundle)
abort "App #{app_bundle} not found" unless app

puts "App: #{app.name} (#{app.bundle_id})"

build = nil
30.times do |i|
  builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, limit: 100)
  build = builds.find { |b| b.version.to_s == version_num.to_s }
  break if build && build.processing_state == "VALID"
  puts "[#{i+1}/30] build #{version_num} state=#{build&.processing_state || 'not-found'}; waiting..."
  sleep 20
end

abort "Build #{version_num} not ready" unless build && build.processing_state == "VALID"

puts "Build: #{build.version} (id=#{build.id}, state=#{build.processing_state})"

group_names.each do |name|
  groups = Spaceship::ConnectAPI::BetaGroup.all(app_id: app.id, limit: 100)
  group  = groups.find { |g| g.name == name }
  if group.nil?
    puts "!! Beta group not found: #{name}"
    next
  end
  begin
    build.add_beta_groups(beta_groups: [group])
    puts "-> Attached build #{build.version} to '#{name}'"
  rescue => e
    puts "-> Could not attach '#{name}': #{e.message}"
  end
end
