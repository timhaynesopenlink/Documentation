#!/usr/bin/env ruby

require 'fileutils'

#
# Generates a table of contents (TOC) for a markdown document.
#
class TocGen
  # Name of markdown file for which a TOC will be generated
  attr_reader :f_md 
  # Maximum heading level to include in the TOC
  attr_reader :max_depth 

  TOC_START_MARKER = "<!--- TOC: Start --->"
  TOC_END_MARKER = "<!--- TOC: End --->"
  TOC_HEADING = "#### Contents"

  # +f_in+:: The name of the markdown document for which a TOC is being generated.
  # +max_depth+:: The maximum heading level to include in the TOC.
  def initialize(f_in, max_depth = 2)
    @f_md = f_in
    @max_depth = max_depth
    Struct.new("TocEntry", :id, :heading, :original_markdown, :level)
  end

  # Returns the TOC start marker, TocGen::TOC_START_MARKER, used by TocGen.
  def self.toc_start_marker
    TOC_START_MARKER
  end

  # Returns the TOC end marker, TocGen::TOC_END_MARKER, used by TocGen.
  def self.toc_end_marker
    TOC_END_MARKER
  end

  # Generates and inserts a TOC into the markdown document.
  #
  # +skip+:: the number of initial headings to skip
  #
  # The TOC will be inserted after the number of headings specified by +skip+.
  # The skipped headings will also be omitted from the TOC.
  #
  # The reason for adding the +skip+ parameter is that the source markdown
  # documents were generated by pandoc. Each document comprises a chapter
  # in which the chapter title is a level 1 heading, and each top level
  # chapter section is also a level 1 heading. +skip+ = 1 omits the
  # chapter heading from the TOC and inserts the TOC below it.
  def insert_toc(skip = 1)
    toc_entries = generate_toc_entries
    return if toc_entries.length == 0
    generate_toc_ids(toc_entries)

    remove_toc # Remove any existing toc and associated anchors

    f_patched = %{#{File.dirname(self.f_md)}/#{File.basename(self.f_md, ".md")}.with_toc.md}
    File.open self.f_md, 'r' do |f_in|
      File.open f_patched, 'w' do |f_out|
        i_toc_entry = 0
        current_toc_entry = toc_entries[0]
        f_in.each do |line|
          if current_toc_entry
            line2 = line.chomp.strip
            if line2 == current_toc_entry.original_markdown
              if i_toc_entry == skip
                # Insert the TOC before this heading.
                write_toc(f_out, toc_entries, skip)
              end

              if i_toc_entry >= skip
                # Insert an anchor tag, for the TOC intra-document link target, before this heading.
                anchor_tag = %{<a id="#{current_toc_entry.id}"></a>\n}
                f_out << anchor_tag
              end

              i_toc_entry += 1
              current_toc_entry = i_toc_entry < toc_entries.length ? toc_entries[i_toc_entry] : nil
            end
          end
          f_out << line
        end
      end
    end
    FileUtils.mv f_patched, self.f_md
  end

  # Removes any existing TOC from the document and, for each TOC entry, 
  # deletes the anchor tag preceding each heading.
  def remove_toc
    return unless TocGen::contains_toc?(self.f_md)
    toc_ids = collect_toc_ids
    f_patched = %{#{File.dirname(self.f_md)}/#{File.basename(self.f_md, ".md")}.without_toc.md}
    File.open self.f_md, 'r' do |f_in|
      File.open f_patched, 'w' do |f_out|
        in_toc = false
        end_of_toc_passed = false
        i_current_id = 0

        f_in.each do |line|
          is_heading_anchor = false
          current_id = i_current_id ? toc_ids[i_current_id] : nil

          case line
            when /#{TOC_START_MARKER}/
              in_toc = true
            when /#{TOC_END_MARKER}/
              end_of_toc_passed = true
            when i_current_id && /id="#{current_id}"/i
              is_heading_anchor = true
              i_current_id = i_current_id < toc_ids.length - 1 ? i_current_id + 1 : nil
            else
              in_toc = false if end_of_toc_passed
          end

          skip_line = in_toc || is_heading_anchor 
          unless skip_line
            f_out << line
          end
        end
      end
    end
    FileUtils.mv f_patched, self.f_md 
  end

  # Indicates if a markdown document contains a TOC created by TocGen  
  # by looking for the presence of TocGen::TOC_START_MARKER.
  def self.contains_toc?(file_name)
    res = nil
    File.open(file_name) do |f|
      res = f.each_line.lazy.select { |line| line.match(/#{TOC_START_MARKER}/) }.first(1).length > 0
    end
    res
  end

private

  # Extracts the headings from the source markdown document
  # up to the depth set by the constructor call.
  #
  # returns:: an array of TocEntry structs
  #
  # Each TocEntry struct holds a heading description.
  # <struct TocEntry id=..., heading=..., original_markdown=..., level=... >
  # Each TocEntry returned has heading and original_markdown attributes
  # set, but not the id attribute. The latter must be set using #generate_toc_ids.
  def generate_toc_entries
    toc_entries = []
    File.open self.f_md, 'r' do |f|
      f.each do |line|
        line.chomp!
        match = /^(\#{1,#{self.max_depth}})([^#]+)/.match(line)
        if match
          toc_entry = Struct::TocEntry.new(nil, match[2].strip, match[0], match[1].length)
          toc_entries << toc_entry
        end
      end
    end
    toc_entries
  end

  # Derives an HTML ID for each heading.
  #
  # +toc_entries+:: an array of TocEntry structs
  #
  # Generates and sets TocEntry.id.
  # The ID must be usable as an HTML ID in an anchor element.
  # For backwards compatibility with HTML 4, an ID
  # should start with a letter and contain only
  # ASCII letters, digits, '_', '-' and '.'
  def generate_toc_ids(toc_entries)
    toc_entries.each_index do |i|
      id = toc_entries[i].heading.downcase.chars.select { |ch| ch =~ /[ A-Za-z0-9_-]/ }
      id = id.join.squeeze(' ').strip.gsub(' ', '-').squeeze('-')
      # Add an id{n} prefix to ensure each ID is unique in the event
      # that the source document includes a duplicated heading.
      id = "id#{i}-" + id
      toc_entries[i].id = id
    end
  end

  def write_toc(f_out, toc_entries, skip)
    f_out << TOC_START_MARKER + "\n"
    f_out << "\n"
    f_out << TOC_HEADING + "\n"
    f_out << "\n"

    toc_entries[skip..toc_entries.length-1].each do |toc_entry|
      indentation = " " * 2 * toc_entry.level
      markdown = indentation + "* [#{toc_entry.heading}](##{toc_entry.id})\n"
      f_out << markdown
    end

    f_out << "\n"
    f_out << TOC_END_MARKER + "\n"
  end

  # Collects the HTML IDs used by links in the TOC.
  #
  # returns:: an array of IDs in order of occurrence in the document.
  def collect_toc_ids
    toc_ids = []
    in_toc = false
    File.open self.f_md, 'r' do |f|
      f.each do |line|
        line.chomp!
        case 
        when /#{TOC_START_MARKER}/.match(line)
          in_toc = true
        when /#{TOC_END_MARKER}/.match(line)
          break
        when in_toc && /\[.*\]\(#(.*)\)/.match(line)
          toc_ids << $1
        end
      end
    end
    toc_ids
  end

end
 
# ===========================================================================

# tocgen = TocGen.new('chapter1.md')
# tocgen.insert_toc

# tocgen = TocGen.new('chapter1.md')
# tocgen.remove_toc