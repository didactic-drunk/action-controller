require "lucky_router"

class ActionController::Router::RouteHandler
  include HTTP::Handler

  def initialize
    @matcher = LuckyRouter::Matcher(Tuple(Action, Bool)).new
    @static_routes = {} of String => Tuple(Action, Bool)
  end

  # Builds the internal representation of a route
  # then searches static routes before checking the matcher
  def search_route(method, req_path, search_path, context : HTTP::Server::Context) : Tuple(Action, Bool)?
    @static_routes.fetch(search_path) do
      if match = @matcher.match(method, req_path)
        context.route_params = match.params
        match.payload
      end
    end
  end

  # Routes requests to the appropriate handler
  # Called from HTTP::Server in server.cr
  def call(context : HTTP::Server::Context)
    method = context.request.method
    req_path = context.request.path
    search_path = "#{method}#{req_path}"

    if action = search_route(method, req_path, search_path, context)
      process_request(search_path, context, action[0], action[1])
    else
      # defined in https://crystal-lang.org/api/latest/HTTP/Handler.html
      call_next(context)
    end
  end

  # We split out the processing of the request for simplified injection of telemetry
  def process_request(search_path, context, controller_dispatch, head_request)
    controller_dispatch.call(context, head_request)
  end

  # Adds a route handler to the system
  # Determines if routes are static or require decomposition and stores them appropriately
  def add_route(method : String, path : String, action : Tuple(Action, Bool))
    @matcher.add(method, path, action)

    unless path.includes?(':') || path.includes?('*')
      lookup_key = "#{method}#{path}"
      @static_routes[lookup_key] = action

      # Add static routes with both trailing and non-trailing / chars
      if lookup_key.ends_with? '/'
        @static_routes[lookup_key[0..-2]] = action
      else
        @static_routes["#{lookup_key}/"] = action
      end
    end
  end
end
