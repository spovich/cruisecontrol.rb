require 'builder_error'

class Subversion
  include CommandLine

  attr_accessor :url, :username, :password

  def initialize(options = {})
    @url, @username, @password, @interactive = 
          options.delete(:url), options.delete(:username), options.delete(:password), options.delete(:interactive)
    raise "don't know how to handle '#{options.keys.first}'" if options.length > 0
  end
  
  def clean_checkout(target_directory, revision = nil, stdout = $stdout)
    FileUtils.rm_rf(target_directory)
    checkout(target_directory, revision, stdout)
  end

  def checkout(target_directory, revision = nil, stdout = $stdout)
    @url or raise 'URL not specified'

    options = [@url, target_directory]
    options << "--username" << @username if @username
    options << "--password" << @password if @password
    options << "--revision" << revision_number(revision) if revision

    # need to read from command output, because otherwise tests break
    execute(svn('co', options)) do |io| 
      begin
        while line = io.gets
          stdout.puts line
        end
      rescue EOFError
      end
    end
  end

  # TODO: change this to return an actual revision object, not a number
  def last_locally_known_revision(project)
    info(project).last_changed_revision
  end

  def latest_revision(project)
    svn_output = execute_in_local_copy(project, log('HEAD', last_locally_known_revision(project)))
    SubversionLogParser.new.parse_log(svn_output).first
  end

  def revisions_since(project, revision_number)
    svn_output = execute_in_local_copy(project, log('HEAD', revision_number))
    new_revisions = SubversionLogParser.new.parse_log(svn_output).reverse
    new_revisions.delete_if { |r| r.number == revision_number }
    new_revisions
  end

  def update(project, revision = nil)
    revision_number = revision ? revision_number(revision) : 'HEAD'
    svn_output = execute_in_local_copy(project, svn('update', "--revision", revision_number))
    SubversionLogParser.new.parse_update(svn_output)
  end
  
  private
  
  def log(from, to)
    svn('log', "--revision", "#{from}:#{to}", '--verbose', '--xml', @url)
  end
  
  def info(project)
    svn_output = execute_in_local_copy(project, svn('info', "--xml"))
    SubversionLogParser.new.parse_info(svn_output)
  end

  def svn(operation, *options)
    command = ["svn"]
    command << "--non-interactive" unless @interactive
    command << operation
    command += options.compact.flatten
    command
  end

  def revision_number(revision)
    revision.respond_to?(:number) ? revision.number : revision.to_i
  end

  def execute_in_local_copy(project, command)
    Dir.chdir(project.local_checkout) do
      err_file_path = project.path + "/svn.err"
      FileUtils.rm_f(err_file_path)
      FileUtils.touch(err_file_path)
      execute(command, :stderr => err_file_path) do |io| 
        result = io.readlines 
        begin 
          error_message = File.open(err_file_path){|f|f.read}.strip.split("\n")[1] || ""
        rescue
          error_message = ""
        ensure
          FileUtils.rm_f(err_file_path)
        end
        raise BuilderError.new(error_message, "svn_error") unless error_message.empty?
        return result
      end
    end
  end
  
  Info = Struct.new :revision, :last_changed_revision, :last_changed_author
end
