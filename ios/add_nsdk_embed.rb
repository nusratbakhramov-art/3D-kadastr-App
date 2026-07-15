#!/usr/bin/env ruby
# Embeds the NSDK SPM framework into the Runner app bundle.
#
# add_scanskit.rb attached the NSDK SPM product to the ScansKit *framework*
# target, so ScansKit links NSDK (hard LC_LOAD_DYLIB @rpath/NSDK.framework/NSDK).
# But frameworks don't embed their own dependencies, so NSDK.framework never
# landed in Runner.app/Frameworks — dlopen'ing ScansKit at runtime would fail
# with "Library not loaded: @rpath/NSDK.framework/NSDK".
#
# Fix: give Runner its own NSDK package-product dependency and reference it from
# an "Embed NSDK" copy-files phase (embed only — Runner itself does not link NSDK,
# ScansKit does). Idempotent: no-op if already embedded.
require 'xcodeproj'

PROJECT = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(PROJECT)
runner  = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

# Reuse the existing NSDK remote package reference wired by add_scanskit.rb.
pkg = project.root_object.package_references.find do |p|
  p.respond_to?(:repositoryURL) && p.repositoryURL.to_s.include?('nsdk-library-xcframework')
end
abort 'NSDK package reference not found — run add_scanskit.rb first.' unless pkg

# Idempotency guard.
if runner.copy_files_build_phases.any? { |ph| ph.name == 'Embed NSDK' }
  abort 'Embed NSDK phase already present — nothing to do.'
end

# Runner needs its own product dependency to reference NSDK in a build file.
dep = runner.package_product_dependencies.find { |d| d.product_name == 'NSDK' }
unless dep
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = pkg
  dep.product_name = 'NSDK'
  runner.package_product_dependencies << dep
end

# Embed-only: copy NSDK.framework into Runner.app/Frameworks, sign on copy.
# No entry in frameworks_build_phase => Runner does not link NSDK (ScansKit does).
embed = runner.new_copy_files_build_phase('Embed NSDK')
embed.symbol_dst_subfolder_spec = :frameworks
bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
bf.product_ref = dep
bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
embed.files << bf

# Keep the embed phase before Flutter's "Thin Binary" run-script to avoid the
# same build cycle that the ScansKit embed hit. Move it just after the existing
# "Embed Frameworks" phase.
runner.build_phases.delete(embed)
anchor = runner.build_phases.index { |ph| ph.respond_to?(:name) && ph.name.to_s.include?('Embed Frameworks') }
insert_at = anchor ? anchor + 1 : runner.build_phases.index(runner.frameworks_build_phase) + 1
runner.build_phases.insert(insert_at, embed)

project.save
puts "Embed NSDK phase added (embed-only, before Thin Binary)."
