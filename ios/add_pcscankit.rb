#!/usr/bin/env ruby
# Creates the PCScanKit framework target in Runner.xcodeproj, adds ios/PCScanKit/*
# sources + vendored static libs, wires build settings, and links the framework
# into the Runner app as Embed + Optional (weak).
#
# Egizak: add_scanskit.rb (nsdk). Farqlar:
#  - SPM paketi YO'Q — PCScan'ning hamma native lib'lari statik (Vendor/lib),
#    OTHER_LDFLAGS orqali (device SDK) linklanadi. => NSDK-uslub qo'shimcha embed
#    KERAK EMAS.
#  - ObjC bridge YO'Q — vendor header'lari sof C (extern "C"). Public headers =
#    umbrella + 3 C header (pcscan_tex/poisson/simplify.h).
#  - Embed cycle'dan qochish uchun PCScanKit MAVJUD "Embed Frameworks" fazasiga
#    qo'shiladi (yangi copy-files faza EMAS — ScansKit shu sabab cycle bergan edi).
#
# Weak + iOS-17: PCScanKit RoomPlan/ObjectCapture (iOS 17) ishlatadi → binar min-17.
# Weak-link → min-15 app iOS 15/16'da ham ochiladi ("#2" u yerda UNSUPPORTED).
#
# Idempotent-ish: PCScanKit target allaqachon bo'lsa abort qiladi.
require 'xcodeproj'

PROJECT = 'Runner.xcodeproj'
PK      = 'PCScanKit'
TEAM    = 'KHGXWF53U9'
PUBLIC_HEADERS = %w[PCScanKit.h pcscan_tex.h pcscan_poisson.h pcscan_simplify.h]
SOURCE_EXT = %w[.swift .mm .m .cpp .cc .c .metal]

project = Xcodeproj::Project.open(PROJECT)
abort "PCScanKit target already exists — restore backup and re-run." if project.targets.any? { |t| t.name == PK }
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

# --- 1. Framework target ---
pk = project.new_target(:framework, PK, :ios, '17.0', project.products_group, :swift)

# Flutter uses a 'Profile' config in addition to Debug/Release — mirror it.
unless pk.build_configurations.any? { |c| c.name == 'Profile' }
  pk.add_build_configuration('Profile', :release)
end

incdir = '$(SRCROOT)/PCScanKit/Vendor/include'
libdir = '$(SRCROOT)/PCScanKit/Vendor/lib'
pk.build_configurations.each do |c|
  s = c.build_settings
  s['IPHONEOS_DEPLOYMENT_TARGET']    = '17.0'
  s['DEFINES_MODULE']                = 'YES'
  s['PRODUCT_NAME']                  = PK
  s['PRODUCT_BUNDLE_IDENTIFIER']     = 'uz.kadastr.kadastr.PCScanKit'
  s['DEVELOPMENT_TEAM']              = TEAM
  s['CODE_SIGN_STYLE']               = 'Automatic'
  s['SWIFT_VERSION']                 = '5.0'
  s['CLANG_CXX_LANGUAGE_STANDARD']   = 'c++17'
  s['CLANG_ENABLE_MODULES']          = 'YES'
  s['ENABLE_BITCODE']                = 'NO'
  s['GENERATE_INFOPLIST_FILE']       = 'YES'
  s['SKIP_INSTALL']                  = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS']       = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  s['HEADER_SEARCH_PATHS']           = ['$(inherited)', incdir]
  s['LIBRARY_SEARCH_PATHS[sdk=iphoneos*]'] = ['$(inherited)', libdir]
  # texrecon/poisson static libs are arm64 DEVICE-only → link them only for the
  # device SDK, so simulator builds still link (heavy recon is device-only anyway).
  s['OTHER_LDFLAGS[sdk=iphoneos*]']  = ['$(inherited)',
    '-lpcscan', '-ltex', '-lmve', '-lpoisson', '-lmeshopt',
    '-ltbb', '-ltbbmalloc', '-ljpeg', '-lpng', '-lz', '-lc++']
  s['MARKETING_VERSION']             = '1.0'
  s['CURRENT_PROJECT_VERSION']       = '1'
end

# --- 2. Group + files (mirror the on-disk PCScanKit/ tree) ---
pk_group = project.main_group.new_group(PK, PK)
headers_phase = pk.headers_build_phase
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
        pk.source_build_phase.add_file_reference(ref, true)
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
        counts[:other] += 1  # Info.plist etc. — ref only, no build phase
      end
    end
  end
end
add_tree.call(pk_group, PK)

# --- 3. Link PCScanKit into Runner: Embed + Optional(weak) + dependency ---
product = pk.product_reference
runner.add_dependency(pk)

link = runner.frameworks_build_phase.add_file_reference(product, true)
link.settings = { 'ATTRIBUTES' => ['Weak'] }

# Reuse Runner's EXISTING "Embed Frameworks" copy phase (positioned before the
# Flutter "Thin Binary" script) — a fresh copy phase after Thin Binary is what
# gave ScansKit a build cycle.
embed = runner.copy_files_build_phases.find { |ph| ph.symbol_dst_subfolder_spec == :frameworks && ph.name.to_s.include?('Embed Frameworks') }
abort 'no existing "Embed Frameworks" phase on Runner' unless embed
ef = embed.add_file_reference(product, true)
ef.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }

project.save
puts "PCScanKit target created."
puts "  sources: #{counts[:sources]}, public headers: #{counts[:public_h]}, project headers: #{counts[:project_h]}, .a refs: #{counts[:libs]}, other: #{counts[:other]}"
puts "  Runner: linked (weak) + embedded (existing Embed Frameworks phase) + dependency."
