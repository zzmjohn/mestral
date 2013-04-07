# This code is free software; you can redistribute it and/or modify it under
# the terms of the new BSD License.
#
# Copyright (c) 2013, Sebastian Staudt

require 'thor'
require 'uri'

require 'mestral'
require 'mestral/repository'
require 'mestral/tape'

class Mestral::CLI < Thor

  class_option :debug, :type => :boolean

  desc 'add-tape', 'Add a hook tape'
  option :name, :desc => 'The name used to identify the tape'
  def add_tape(url)
    name = options[:name] || File.basename(url, '.git')
    tape = Mestral::Tape.new name
    if tape.exists?
      $stdout << "A tape with the name '#{tape.name}' already exists. Do you want to update it? [Y/n] "
      if $stdin.gets.strip.downcase != 'y'
        update_tape tape
      else
        puts 'Aborted.'
        return
      end
    else
      url = File.expand_path url if URI(url).scheme.nil?
      if tape.git_clone url
        puts "Successfully cloned tape '#{tape.name}'."
      else
        $stdout << 'Cloning the tape failed. Do you still want to keep it? [y/N] '
        tape.destroy if $stdin.gets.strip.downcase != 'y'
        return
      end
    end
  end

  desc 'disable', 'Disable a hooklet for the given Git hook'
  def disable(hook_name, tape_name, hooklet_name)
    init_repository

    hook = Mestral::Repository.current.hook hook_name

    if hook.is_a? Mestral::Hook::Native
      puts "The '#{hook_name}' hook is a native hook and cannot execute hooklets."
      return
    end

    unless hook.hooklets.any? { |hooklet| hooklet.tape.name == tape_name && hooklet.name == hooklet_name }
      puts "The hooklet '#{hooklet_name}' (#{tape_name}) is not enabled for the '#{hook_name}' hook."
      return
    end

    Mestral::Repository.current.git "config --unset-all mestral.hooks.#{tape_name}.#{hooklet_name} #{hook_name}"
  end

  desc 'enable', 'Enable a hooklet for the given Git hook'
  def enable(hook_name, tape_name, hooklet_name)
    init_repository

    hook = Mestral::Repository.current.hook hook_name

    if hook.is_a? Mestral::Hook::Native
      puts "The '#{hook_name}' hook is a native hook and cannot execute hooklets."
      return
    end

    if hook.hooklets.any? { |hooklet| hooklet.tape.name == tape_name && hooklet.name == hooklet_name }
      puts "The hooklet '#{hooklet}' (#{tape_name}) was is already enabled for the '#{hook_name}' hook."
      return
    end

    Mestral::Repository.current.git "config --add mestral.hooks.#{tape_name}.#{hooklet_name} #{hook_name}"
  end

  desc 'execute-hook', 'Execute a hook'
  def execute_hook(hook_path)
    init_repository

    hook_name = File.basename hook_path

    debug "Executing #{hook_name}..."

    hook = Mestral::Repository.current.hook hook_name
    exit(1) unless hook.execute
  end

  desc 'list', 'List available hooks'
  option :enabled, :type => :boolean, :desc => 'Only list hooks currently enabled in the current repository'
  def list
    hooks = []

    if options[:enabled]
      init_repository

      hooks = Mestral::Repository.current.hooks
    else
      hooks = Mestral::Tape.all.map(&:hooklets).flatten.compact
    end

    if hooks.empty?
      if options[:enabled]
        puts 'There are no enabled hooks in the current repository.'
      else
        puts 'There are no available hooks.'
        puts "Use `#$0 add-tape` to add a hook tape."
      end
    else
      puts "List of #{'enabled ' if options[:enabled]}Git hooks"

      hooks.each do |hook|
        puts " - #{hook.name}"
        if hook.is_a? Mestral::Hook::Multi
          hook.hooklets.each do |hooklet|
            puts "   - #{hooklet.name}"
          end
        end
      end
    end
  end

  desc 'update-tapes', 'Updates one or more hook tapes'
  def update_tapes(*tapes)
    if tapes.empty?
      tapes = Mestral::Tape.all
    else
      tapes.map! do |tape_name|
        tape = Mestral::Tape.find tape_name
        puts "Tape '#{tape_name}' does not exist. Ignoring." if tape.nil?
        tape
      end
    end

    tapes.compact.each &method(:update_tape)
  end

  no_commands do

    def debug(message)
      puts message if options[:debug]
    end

    def init_repository
      Mestral::Repository.current = Dir.pwd
    end

    def update_tape(tape)
      current_sha = tape.sha
      new_sha = tape.git_pull

      if new_sha == current_sha
        puts "Tape '#{tape.name}' is already up-to-date."
      else
        puts "Updated tape '#{tape.name}' from #{current_sha} to #{new_sha}"
      end
    end

  end

end