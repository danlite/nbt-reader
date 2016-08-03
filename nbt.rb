#!/usr/bin/env ruby

require 'zlib'
require 'trollop'
require 'yaml'

module NBT
  class Token
    attr_reader :type, :name, :data

    def initialize(type, name, data)
      @type = type
      @name = name
      @data = data
    end

    def to_s
      "#{@type}:#{@name}:#{@data}"
    end

  end

  class NBTParser

    def self.tag_type_for_id(id)
      case id
      when 0x00 then 'End'
      when 0x01 then 'Byte'
      when 0x02 then 'Short'
      when 0x03 then 'Int'
      when 0x04 then 'Long'
      when 0x05 then 'Float'
      when 0x06 then 'Double'
      when 0x07 then 'Byte_Array'
      when 0x08 then 'String'
      when 0x09 then 'List'
      when 0x0a then 'Compound'
      when 0x0b then 'Int_Array'
      else raise "Unknown tag ID: #{id}"
      end
    end

    def initialize(file)
      @file = file
      @tokens = []
      @hexstring = ''
      @current_tag_name
    end

    def file
      @file
    end

    def tokenize
      until @file.eof? do
        parse_tag
      end
      @tokens
    end

    def log_bytes(bytes)
      hex_bytes = bytes.map do |b|
        b.to_s(16)
      end
      hex = hex_bytes.join.rjust(bytes.length * 2, '0')
      @hexstring << hex + ' '
    end

    def save_token(opts)
      type = NBTParser.tag_type_for_id(opts[:type] || @current_tag_id)
      opts[:name] = @current_tag_name unless opts.has_key? :name

      token = Token.new(type, opts[:name], opts[:info])

      @tokens << token
    end

    def save_current_token(info=nil)
      save_token({:info => info})
      @current_tag_name = nil
      @current_tag_id = nil
    end

    def read_id
      read_byte
    end

    def read_byte
      read(1).unpack('c').first
    end

    def read_short
      read(2).unpack('s>').first
    end

    def read_int
      read(4).unpack('i>').first
    end

    def read_long
      read(8).unpack('l>').first
    end

    def read_float
      read(4).unpack('g').first
    end

    def read_double
      read(8).unpack('G').first
    end

    def read_string
      length = read_short
      read(length)
    end

    def read(n=1)
      string = file.read(n)
      # log_bytes(string.bytes)
      string
    end

    def parse_tag
      id = @current_tag_id = read_id

      name_length = 0
      if @current_tag_id != 0x00
        name_length = read_short
      end

      if name_length > 0
        @current_tag_name = read(name_length)
      end

      parse_payload_for_id(@current_tag_id)
      id
    end

    def parse_payload_for_id(id)
      case id
      when 0x00 then parse_end
      when 0x01 then parse_byte
      when 0x02 then parse_short
      when 0x03 then parse_int
      when 0x04 then parse_long
      when 0x05 then parse_float
      when 0x06 then parse_double
      when 0x07 then parse_byte_array
      when 0x08 then parse_string
      when 0x09 then parse_list
      when 0x0a then parse_compound
      when 0x0b then parse_int_array
      else raise "Unknown tag ID: #{id}"
      end
    end

    def parse_end
      save_current_token
    end

    def parse_byte
      byte = read_byte
      save_current_token byte
    end

    def parse_short
      short = read_short
      save_current_token short
    end

    def parse_int
      integer = read_int
      save_current_token integer
    end

    def parse_long
      long = read_long
      save_current_token long
    end

    def parse_float
      float = read_float
      save_current_token float
    end

    def parse_double
      double = read_double
      save_current_token double
    end

    def parse_byte_array
      length = read_int
      save_current_token length
      length.times do
        @current_tag_id = 0x01
        parse_byte
      end
    end

    def parse_string
      save_current_token read_string
    end

    def parse_list
      tag_id = read_byte
      size = read_int
      save_current_token([ NBTParser.tag_type_for_id(tag_id), size ])
      size.times do
        @current_tag_id = tag_id
        parse_payload_for_id(tag_id)
      end
    end

    def parse_compound
      save_current_token
      id = parse_tag
      until id == 0x00 do
        id = parse_tag
      end
    end

    def parse_int_array
      size = read_int
      save_current_token size
      size.times do
        @current_tag_id = 0x03
        parse_int
      end
    end

    def parse
      root = nil
      stack = []
      stack_index_size = {}
      tokenize

      @tokens.each do |token|
        this = nil
        container = false
        size = nil
        parent = stack.last

        if token.type == 'End'
          stack.pop
        elsif token.type == 'Compound'
          this = {}
          container = true
          root = this if stack.length == 0
        elsif token.type == 'List'
          size = token.data[1]
          this = []
          container = true
        elsif token.type == 'Int_Array' || token.type == 'Byte_Array'
          size = token.data
          this = []
          container = true
        else
          this = token.data
        end

        tag_complete = !container

        if this
          if parent.is_a? Hash
            parent[token.name] = this
          elsif parent.is_a? Array
            parent << this
          else
            raise "parent is invalid type '#{parent.class}'" unless root == this
          end
        end

        if size
          stack_index_size[stack.length] = size
          tag_complete = (size == 0)
        end

        if container
          stack << this
        end

        if tag_complete
          is_array = false
          begin
            parent_index = stack.length - 1
            parent = stack[parent_index]
            target_length = stack_index_size[parent_index]
            is_array = parent.is_a? Array

            break unless is_array

            if target_length == parent.length
              stack.pop
            else
              break
            end
          end while is_array
        end
      end

      root
    end
  end

  def self.parse(filename, compressed=true)
    results = nil
    File.open(filename, 'rb') do |file|
      io = compressed ? Zlib::GzipReader.new(file) : file
      parser = NBTParser.new(io)
      results = parser.parse
    end
    results
  end

end


if ARGV.length > 0
  opts = Trollop::options do
    banner 'nbt.rb [options] nbt-file.dat'
    opt :uncompressed, 'Read file as uncompressed data', :default => false
  end

  filename = ARGV.shift

  raise 'Missing filename' unless filename

  puts YAML.dump NBT.parse(filename, !opts[:uncompressed])
end
