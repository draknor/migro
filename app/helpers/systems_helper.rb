module SystemsHelper

  def page_record_range(count, page, max_per_page)
    page ||= 1
    count ||= 0
    max_per_page ||= 25
    start_id = (page-1) * max_per_page + 1
    end_id = start_id-1 + count
    count > 0 ? "#{start_id} - #{end_id}" : '[none found]'
  end

end
