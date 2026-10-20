module ScreensHelper
  # A table header that links to the same page sorted by `column`, toggling direction.
  # The link stays inside the "screens" Turbo Frame and advances the URL (back button works).
  def sortable_header(title, column)
    column = column.to_s
    active = params[:sort] == column
    ascending = params[:direction] == "asc"
    next_direction = active && ascending ? "desc" : "asc"

    link = link_to screens_path(request.query_parameters.merge("sort" => column, "direction" => next_direction).except("page")),
                   class: "ns-table__sort", data: { turbo_action: "advance" } do
      safe_join([ title, (tag.span(ascending ? "▲" : "▼", class: "ns-table__sort-icon", aria: { hidden: true }) if active) ].compact, " ")
    end
    tag.th(link, class: "ns-table__head", aria: { sort: (ascending ? "ascending" : "descending" if active) })
  end
end
