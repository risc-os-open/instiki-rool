# Controller responsible for serving files and pictures.

#require 'zip/zip'

class FileController < ApplicationController

  layout 'default'

  before_action :check_authorized
  before_action :check_allow_uploads, :dnsbl_check, :except => [:file]

  skip_before_action :hubssolib_beforehand, only: [:file]
  skip_after_action  :hubssolib_afterwards, only: [:file]

  # 2011-03-14 (ADH): Hub integration.

  HUBSSOLIB_PERMISSIONS = HubSsoLib::Permissions.new({
    :delete => [ :admin, :webmaster ]
  })

  def self.hubssolib_permissions
    HUBSSOLIB_PERMISSIONS
  end

  def file
    @file_name = params['id']
    if params['file']
      return unless is_post and check_allow_uploads
      # form supplied
      new_file = @web.wiki_files.create(
        file_name:   params.dig('file', 'file_name'  ),
        description: params.dig('file', 'description'),
        content:     params.dig('file', 'content'    )
      )
      if new_file.valid?
        flash[:info] = "File '#{@file_name}' successfully uploaded"
        redirect_to(params['referring_page'])
      else
        # pass the file with errors back into the form
        @file = new_file
        render
      end
    else
      # no form supplied, this is a request to download the file
      file = @web.files_path.join(@file_name)
      if File.exist?(file)
        send_file(file)
      else
        return unless check_allow_uploads
        @file = WikiFile.new(:file_name => @file_name)
        render(formats: [:html])
      end
    end
  end

  def delete
    @file_name = params['id']
    file = WikiFile.find_by_file_name(@file_name)
    unless file
      flash[:error] = "File '#{@file_name}' not found."
      redirect_to_page(@page_name)
    end
    system_password = params['system_password']
    if system_password
      return unless is_post
      # form supplied
      if wiki.authenticate(system_password)
         file.destroy
         flash[:info] = "File '#{@file_name}' deleted."
       else
        flash[:error] = "System Password incorrect."
      end
      redirect_to_page(@page_name)
    else
    # no system password supplied, display the form
    end
  end

  def cancel_upload
    return_to_last_remembered
  end

  def import
    if params['file']
      @problems = []
      import_file_name = "#{@web.address}-import-#{Time.now.strftime('%Y-%m-%d-%H-%M-%S')}.zip"
      import_from_archive(params['file'].path)
      if @problems.empty?
        flash[:info] = 'Import successfully finished'
      else
        flash[:error] = 'Import finished, but some pages were not imported:<li>' +
            @problems.join('</li><li>') + '</li>'
      end
      return_to_last_remembered
    else
      # to template
    end
  end

  protected

    def check_authorized
      if authorized? or @web.published?
        return true
      else
        @hide_navigation  = true

        render(
          'error',
          status:  403,
          formats: [:html],
          locals:  { message: 'This web is private' }
        )

        return false
      end
    end

    def check_allow_uploads
      unless @web
        render(
          'error',
          status:  404,
          formats: [:html],
          locals:  { message: "Web #{params['web'].inspect} not found" }
        )

        return false
      end

      if @web.allow_uploads? and authorized?
        return true
      else
        @hide_navigation  = true

        render(
          'error',
          status:  403,
          formats: [:html],
          locals:  { message: 'File uploads are blocked by the webmaster' }
        )

        return false
      end
    end

  private

    def import_from_archive(archive)
      Rails.logger.info "Importing pages from #{archive}"
      zip = Zip::ZipInputStream.open(archive)
      while (entry = zip.get_next_entry) do
        ext_length = File.extname(entry.name).length
        page_name = entry.name[0..-(ext_length + 1)]
        page_content = entry.get_input_stream.read
        Rails.logger.info "Processing page '#{page_name}'"
        begin
          existing_page = @wiki.read_page(@web.address, page_name)
          if existing_page
            if existing_page.content == page_content
              Rails.logger.info "Page '#{page_name}' with the same content already exists. Skipping."
              next
            else
              Rails.logger.info "Page '#{page_name}' already exists. Adding a new revision to it."
              wiki.revise_page(@web.address, page_name, page_name, page_content, Time.now, @author, PageRenderer.new)
            end
          else
            wiki.write_page(@web.address, page_name, page_content, Time.now, @author, PageRenderer.new)
          end
        rescue => e
          Rails.logger.error(e)
          @problems << "#{page_name} : #{e.message}"
        end
      end
      Rails.logger.info "Import from #{archive} finished"
    end

end
