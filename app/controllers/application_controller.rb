class ApplicationController < ActionController::Base
  # Rails 8's generated sign-in (bin/rails generate authentication). Pages require a
  # session unless their controller says `allow_unauthenticated_access`.
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
