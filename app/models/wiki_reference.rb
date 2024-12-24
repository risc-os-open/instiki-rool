class WikiReference < ApplicationRecord

  LINKED_PAGE = 'L'
  WANTED_PAGE = 'W'
  REDIRECTED_PAGE = 'R'
  INCLUDED_PAGE = 'I'
  CATEGORY = 'C'
  AUTHOR = 'A'
  FILE = 'F'
  WANTED_FILE = 'E'

  belongs_to :page
  validates_inclusion_of :link_type, :in => [LINKED_PAGE, WANTED_PAGE, REDIRECTED_PAGE, INCLUDED_PAGE, CATEGORY, AUTHOR, FILE, WANTED_FILE]

  def referenced_name
    read_attribute(:referenced_name).as_utf8
  end

  def self.link_type(web, page_name)
    if web.has_page?(page_name) || self.page_that_redirects_for(web, page_name)
      LINKED_PAGE
    else
      WANTED_PAGE
    end
  end

  def self.pages_that_reference(web, page_name)
    query = 'SELECT name FROM pages JOIN wiki_references ' +
      'ON pages.id = wiki_references.page_id ' +
      'WHERE wiki_references.referenced_name = ? ' +
      "AND wiki_references.link_type in ('#{LINKED_PAGE}', '#{WANTED_PAGE}', '#{INCLUDED_PAGE}') " +
      "AND pages.web_id = '#{web.id}'"
    names = connection.select_all(sanitize_sql([query, page_name])).map { |row| row['name'] }
  end

  def self.pages_that_link_to(web, page_name)
    query = 'SELECT name FROM pages JOIN wiki_references ' +
      'ON pages.id = wiki_references.page_id ' +
      'WHERE wiki_references.referenced_name = ? ' +
      "AND wiki_references.link_type in ('#{LINKED_PAGE}','#{WANTED_PAGE}') " +
      "AND pages.web_id = '#{web.id}'"
    names = connection.select_all(sanitize_sql([query, page_name])).map { |row| row['name'] }
  end

  def self.pages_that_link_to_file(web, file_name)
    query = 'SELECT name FROM pages JOIN wiki_references ' +
      'ON pages.id = wiki_references.page_id ' +
      'WHERE wiki_references.referenced_name = ? ' +
      "AND wiki_references.link_type in ('#{FILE}') " +
      "AND pages.web_id = '#{web.id}'"
    names = connection.select_all(sanitize_sql([query, file_name])).map { |row| row['name'] }
  end

  def self.pages_that_include(web, page_name)
    query = 'SELECT name FROM pages JOIN wiki_references ' +
      'ON pages.id = wiki_references.page_id ' +
      'WHERE wiki_references.referenced_name = ? ' +
      "AND wiki_references.link_type = '#{INCLUDED_PAGE}' " +
      "AND pages.web_id = '#{web.id}'"
    names = connection.select_all(sanitize_sql([query, page_name])).map { |row| row['name'] }
  end

  def self.pages_redirected_to(web, page_name)
    names = []
    redirected_pages = []
    page = web.page(page_name)
    redirected_pages.concat page.redirects
    redirected_pages.concat Thread.current[:page_redirects][page] if
            Thread.current[:page_redirects] && Thread.current[:page_redirects][page]
    redirected_pages.uniq.each { |name| names.concat self.pages_that_reference(web, name) }
    names.uniq
  end

  def self.page_that_redirects_for(web, page_name)
    query = 'SELECT name FROM pages JOIN wiki_references ' +
      'ON pages.id = wiki_references.page_id ' +
      'WHERE wiki_references.referenced_name = ? ' +
      "AND wiki_references.link_type = '#{REDIRECTED_PAGE}' " +
      "AND pages.web_id = '#{web.id}'"

    row = connection.select_one(sanitize_sql([query, page_name]))
    row&.dig('name')
  end

  def self.pages_in_category(web, category)
    return (
      Page
        .joins(:wiki_references)
        .where(wiki_references: { link_type: CATEGORY, referenced_name: category })
        .where(pages:           { web_id: web.id })
        .order(name: :asc)
    )
  end

  def self.list_categories(web)
    return (
      WikiReference
        .select(:referenced_name).distinct
        .left_outer_joins(:page)
        .where(wiki_references: { link_type: CATEGORY })
        .where(pages:           { web_id: web.id })
        .order(referenced_name: :asc)
        .pluck(:referenced_name)
    )
  end

  def wiki_word?
    linked_page? or wanted_page?
  end

  def wiki_link?
    linked_page? or wanted_page? or file? or wanted_file?
  end

  def linked_page?
    link_type == LINKED_PAGE
  end

  def redirected_page?
    link_type == REDIRECTED_PAGE
  end

  def wanted_page?
    link_type == WANTED_PAGE
  end

  def included_page?
    link_type == INCLUDED_PAGE
  end

  def file?
    link_type == FILE
  end

  def wanted_file?
    link_type == WANTED_FILE
  end

  def category?
    link_type == CATEGORY
  end

end
