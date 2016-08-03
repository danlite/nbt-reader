#!/usr/bin/env ruby

require 'trollop'
require 'rmagick'
include Magick

args = []
while ARGV.length > 0 do args << ARGV.shift end

output_filename = nil

require './nbt'

module NBT
  def self.base_map_colors
    @base_map_colors ||= [
      nil,
      [127,178,56],
      [247,233,163],
      [167,167,167],
      [255,0,0],
      [160,160,255],
      [167,167,167],
      [0,124,0],
      [255,255,255],
      [164,168,184],
      [183,106,47],
      [112,112,112],
      [64,64,255],
      [104,83,50],
      [255,252,245],
      [216,127,51],
      [178,76,216],
      [102,153,216],
      [229,229,51],
      [127,204,25],
      [242,127,165],
      [76,76,76],
      [153,153,153],
      [76,127,153],
      [127,63,178],
      [51,76,178],
      [102,76,51],
      [102,127,51],
      [153,51,51],
      [25,25,25],
      [250,238,77],
      [92,219,213],
      [74,128,255],
      [0,217,58],
      [21,20,31],
      [112,2,0]
    ]
  end

  def self.map_color_for_id(id)
    offset = id % 4
    base_id = (id - offset) / 4
    color = base_map_colors[base_id]
    if color
      multiplier = case offset
      when 0 then 180/255.0
      when 1 then 220/255.0
      when 2 then 1
      when 3 then 135/255.0
      end

      color = color.map do |c|
        c * multiplier
      end
    end
    color
  end

  class Map

    def initialize(nbt, output)
      data = nbt['data']

      width = data['width']
      height = data['height']
      num_colors = width*height
      colors = data['colors']

      raise "expected #{num_colors} colors, got #{colors.length}" if colors.length != num_colors

      canvas = Image.new(width, height) do
        self.background_color = 'transparent'
      end
      gc = Draw.new

      height.times do |row|
        width.times do |column|
          color_id = colors[row*width + column]
          rgb = NBT.map_color_for_id(color_id)
          next unless rgb

          gc.fill "rgb(#{rgb.join(',')})"
          gc.point column, row
        end
      end

      gc.draw canvas
      canvas.scale! 4.0
      canvas.write output
    end

  end
end

if args.length > 0
  parser = Trollop::Parser.new do
    banner 'map.rb [options] map-file.dat'
    opt :output, 'Map image output file', :type => :string
  end

  opts = Trollop::with_standard_exception_handling parser do
    parser.parse args
  end

  output_filename = opts[:output]
  raise 'Missing map image output file' unless output_filename

  filename = args.shift
  nbt = NBT.parse(filename)
  NBT::Map.new(nbt, output_filename)
end
