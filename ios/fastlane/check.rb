lane :check do
  load_app_store_key!
  require 'spaceship'
  app = Spaceship::ConnectAPI::App.find("com.calc.domeClient")
  UI.message "App: #{app.name} (#{app.bundle_id})"
  builds = app.get_builds(includes: "buildBetaDetail", limit: 8, sort: "-uploadedDate")
  builds.each do |b|
    bd = b.build_beta_detail rescue nil
    UI.message "  v=#{b.version}  processing=#{b.processing_state}  expired=#{b.expired}  int=#{bd&.internal_build_state}  ext=#{bd&.external_build_state}  uploaded=#{b.uploaded_date}"
  end
  groups = app.get_beta_groups(limit: 50)
  UI.message "=== Beta Groups ==="
  groups.each do |g|
    bs = g.get_builds(limit: 3, sort: "-uploadedDate") rescue []
    UI.message "  '#{g.name}'  builds: #{bs.map{|b|b.version}.join(', ')}"
  end
end
