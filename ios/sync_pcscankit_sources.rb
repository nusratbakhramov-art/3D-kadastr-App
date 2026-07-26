#!/usr/bin/env ruby
# frozen_string_literal: true
#
# PCScanKit re-sync yordamchisi.
#
# `add_pcscankit.rb` target'ni NOLDAN yaratadi va u mavjud bo'lsa abort qiladi —
# ya'ni upstream'dan yangi fayl kelganda uni qayta ishlatib bo'lmaydi. Bu skript
# o'sha bo'shliqni to'ldiradi: diskdagi `PCScanKit/` daraxtini target bilan
# solishtiradi va faqat YETISHMAYOTGANini qo'shadi. Idempotent — qayta ishga
# tushirsa "0 qo'shildi" deydi.
#
# Ishlatish:  cd ios && ruby sync_pcscankit_sources.rb [--dry-run]

require 'xcodeproj'

PROJECT = 'Runner.xcodeproj'
PK      = 'PCScanKit'
PUBLIC_HEADERS = %w[PCScanKit.h pcscan_tex.h pcscan_poisson.h pcscan_simplify.h].freeze
SOURCE_EXT = %w[.swift .mm .m .cpp .cc .c .metal].freeze

dry_run = ARGV.include?('--dry-run')

project = Xcodeproj::Project.open(PROJECT)
pk = project.targets.find { |t| t.name == PK } or
  abort "#{PK} target topilmadi — avval add_pcscankit.rb ni ishga tushiring."

# Target allaqachon biladigan fayllar (absolyut yo'l bo'yicha).
known = {}
(pk.source_build_phase.files_references + pk.headers_build_phase.files_references)
  .compact.each { |r| known[File.expand_path(r.real_path.to_s)] = true }

# Diskdagi daraxtni kuzatib, guruhlarni kerak bo'lganda yaratamiz.
added = Hash.new(0)

walk = lambda do |group, disk_dir|
  Dir.children(disk_dir).sort.each do |name|
    next if name.start_with?('.')
    path = File.join(disk_dir, name)

    if File.directory?(path)
      child = group.groups.find { |g| g.display_name == name } ||
              (dry_run ? nil : group.new_group(name, name))
      # --dry-run: guruh yo'q bo'lsa ham ichkariga qarab hisoblayveramiz.
      walk.call(child, path) if child
      next
    end

    ext = File.extname(name).downcase
    next unless SOURCE_EXT.include?(ext) || ext == '.h'
    next if known[File.expand_path(path)]

    rel = path.sub(%r{\A#{Regexp.escape(PK)}/}, '')
    if dry_run
      puts "  + #{rel}"
      added[ext == '.h' ? :headers : :sources] += 1
      next
    end

    ref = group.new_reference(name)
    if ext == '.h'
      bf = pk.headers_build_phase.add_file_reference(ref, true)
      public_h = PUBLIC_HEADERS.include?(name)
      bf.settings = { 'ATTRIBUTES' => [public_h ? 'Public' : 'Project'] }
      added[:headers] += 1
    else
      pk.source_build_phase.add_file_reference(ref, true)
      added[:sources] += 1
    end
    puts "  + #{rel}"
  end
end

pk_group = project.main_group.groups.find { |g| g.display_name == PK } or
  abort "'#{PK}' guruhi topilmadi — pbxproj kutilganidan boshqacha."

walk.call(pk_group, PK)

total = added[:sources] + added[:headers]
if total.zero?
  puts "PCScanKit: target diskdagi daraxt bilan mos — qo'shiladigan fayl yo'q."
else
  puts "PCScanKit: #{added[:sources]} manba, #{added[:headers]} header qo'shildi."
  if dry_run
    puts '(--dry-run — pbxproj YOZILMADI)'
  else
    project.save
    puts "#{PROJECT} saqlandi."
  end
end
