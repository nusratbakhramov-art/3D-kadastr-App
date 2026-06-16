#!/usr/bin/env ruby
# Adds ios/Runner/RoomScan/*.swift to the Runner target (idempotent).
require 'xcodeproj'

project = Xcodeproj::Project.open('Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

# Find the "Runner" group (path or name), then a RoomScan subgroup under it.
runner_group = project.main_group.children.find { |g|
  g.is_a?(Xcodeproj::Project::Object::PBXGroup) && (g.display_name == 'Runner' || g.path == 'Runner')
} || project.main_group

roomscan = runner_group.children.find { |g|
  g.respond_to?(:display_name) && g.display_name == 'RoomScan'
}
roomscan ||= runner_group.new_group('RoomScan', 'RoomScan')

existing = roomscan.files.map { |f| File.basename(f.path.to_s) }
# Already-compiled file names in the target (avoid duplicate build refs).
in_target = target.source_build_phase.files.map { |bf| bf.file_ref&.path && File.basename(bf.file_ref.path.to_s) }.compact

# Prune refs for RoomScan files deleted from disk (e.g. removed CoverageOverlayView).
removed = []
roomscan.files.dup.each do |ref|
  base = File.basename(ref.path.to_s)
  next if File.exist?(File.join('Runner/RoomScan', base))
  target.source_build_phase.files.dup.each { |bf| bf.remove_from_project if bf.file_ref == ref }
  ref.remove_from_project
  removed << base
end

added = []
Dir.glob('Runner/RoomScan/*.swift').sort.each do |path|
  base = File.basename(path)
  next if in_target.include?(base)
  ref = existing.include?(base) ? roomscan.files.find { |f| File.basename(f.path.to_s) == base }
                                : roomscan.new_reference(base)
  target.source_build_phase.add_file_reference(ref, true)
  added << base
end

project.save
puts "RoomScan group has #{roomscan.files.size} file refs."
puts "Removed #{removed.size}: #{removed.join(', ')}"
puts "Added #{added.size} to Runner target: #{added.join(', ')}"
