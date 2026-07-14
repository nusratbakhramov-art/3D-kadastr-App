#!/usr/bin/env ruby
# Creates the ScansKit framework target in Runner.xcodeproj, adds ios/ScansKit/*
# sources, wires build settings + the NSDK remote SPM package, and links the
# framework into the Runner app target as Embed + Optional (weak).
#
# Weak + iOS-17 target: ScansKit uses iOS-17 nsdk APIs, so its binary is min-17.
# It is weak-linked so the min-15 app still launches on iOS 15/16 (the "#1"
# entry is guarded by `if #available(iOS 17)`). Final launch check = device (Phase 5).
#
# Idempotent-ish: aborts if a ScansKit target already exists — restore first
# (cp /tmp/project.pbxproj.bak Runner.xcodeproj/project.pbxproj) before re-running.
require 'xcodeproj'

PROJECT = 'Runner.xcodeproj'
SK      = 'ScansKit'
TEAM    = 'KHGXWF53U9'
NSDK_URL = 'https://github.com/nianticspatial/nsdk-library-xcframework'
NSDK_VER = '4.1.0-26051913'
PUBLIC_HEADERS = %w[ScansKit.h NSDKXAtlasBridge.h MeshOptBridge.h TexIOSBridge.h]
SOURCE_EXT = %w[.swift .mm .m .cpp .cc .c .metal]

project = Xcodeproj::Project.open(PROJECT)
abort "ScansKit target already exists — restore backup and re-run." if project.targets.any? { |t| t.name == SK }
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

# --- 1. Framework target ---
sk = project.new_target(:framework, SK, :ios, '17.0', project.products_group, :swift)

# Flutter uses a 'Profile' config in addition to Debug/Release — mirror it.
unless sk.build_configurations.any? { |c| c.name == 'Profile' }
  sk.add_build_configuration('Profile', :release)
end

libdir = '$(SRCROOT)/ScansKit/ThirdParty/texios/lib'
sk.build_configurations.each do |c|
  s = c.build_settings
  s['IPHONEOS_DEPLOYMENT_TARGET']    = '17.0'
  s['DEFINES_MODULE']                = 'YES'
  s['PRODUCT_NAME']                  = SK
  s['PRODUCT_BUNDLE_IDENTIFIER']     = 'uz.kadastr.kadastr.ScansKit'
  s['DEVELOPMENT_TEAM']              = TEAM
  s['CODE_SIGN_STYLE']               = 'Automatic'
  s['SWIFT_VERSION']                 = '5.0'
  s['CLANG_CXX_LANGUAGE_STANDARD']   = 'c++17'
  s['CLANG_ENABLE_MODULES']          = 'YES'
  s['ENABLE_BITCODE']                = 'NO'
  s['GENERATE_INFOPLIST_FILE']       = 'YES'
  s['SKIP_INSTALL']                  = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS']       = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  s['LIBRARY_SEARCH_PATHS']          = ['$(inherited)', libdir]
  # texios static libs are arm64 DEVICE-only → link them only for the device SDK,
  # so simulator builds still link (HQ texturing is #if'd out there).
  s['OTHER_LDFLAGS[sdk=iphoneos*]']  = ['$(inherited)', '-ltexios', '-ljpeg', '-lpng', '-ltiff', '-ltbb', '-lz', '-lc++']
  s['MARKETING_VERSION']             = '1.0'
  s['CURRENT_PROJECT_VERSION']       = '1'
end

# --- 2. Group + files (mirror the on-disk ScansKit/ tree) ---
sk_group = project.main_group.new_group(SK, SK)
headers_phase = sk.headers_build_phase
counts = Hash.new(0)

add_tree = lambda do |group, disk_dir|
  Dir.children(disk_dir).sort.each do |name|
    next if name.start_with?('.')
    path = File.join(disk_dir, name)
    if File.directory?(path)
      add_tree.call(group.new_group(name, name), path)
    else
      ext = File.extname(name).downcase
      ref = group.new_reference(name)
      if SOURCE_EXT.include?(ext)
        sk.source_build_phase.add_file_reference(ref, true)
        counts[:sources] += 1
      elsif ext == '.h'
        bf = headers_phase.add_file_reference(ref, true)
        if PUBLIC_HEADERS.include?(name)
          bf.settings = { 'ATTRIBUTES' => ['Public'] }
          counts[:public_h] += 1
        else
          bf.settings = { 'ATTRIBUTES' => ['Project'] }
          counts[:project_h] += 1
        end
      elsif ext == '.a'
        counts[:libs] += 1  # file ref only (linked via OTHER_LDFLAGS), no build phase
      else
        counts[:other] += 1
      end
    end
  end
end
add_tree.call(sk_group, SK)

# --- 3. NSDK remote SPM package on ScansKit ---
pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = NSDK_URL
pkg.requirement = { 'kind' => 'exactVersion', 'version' => NSDK_VER }
project.root_object.package_references << pkg
dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'NSDK'
sk.package_product_dependencies << dep
bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
bf.product_ref = dep
sk.frameworks_build_phase.files << bf

# --- 4. Link ScansKit into Runner: Embed + Optional(weak) + dependency ---
product = sk.product_reference
runner.add_dependency(sk)

link = runner.frameworks_build_phase.add_file_reference(product, true)
link.settings = { 'ATTRIBUTES' => ['Weak'] }

embed = runner.new_copy_files_build_phase('Embed ScansKit')
embed.symbol_dst_subfolder_spec = :frameworks
ef = embed.add_file_reference(product, true)
ef.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }

project.save
puts "ScansKit target created."
puts "  sources: #{counts[:sources]}, public headers: #{counts[:public_h]}, project headers: #{counts[:project_h]}, .a refs: #{counts[:libs]}, other: #{counts[:other]}"
puts "  NSDK SPM: #{NSDK_URL} @ #{NSDK_VER}"
puts "  Runner: linked (weak) + embedded (Embed ScansKit) + dependency."
