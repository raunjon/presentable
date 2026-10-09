# frozen_string_literal: true

Dummy::Application.routes.draw do
  scope defaults: { format: "json" } do
    get "leads/with_metadata", to: "leads#with_metadata"
    get "leads", to: "leads#index"
    get "layered_leads", to: "layered_leads#index"
    get "leads/:id", to: "leads#show"
    get "errors/:action", controller: "errors"
    get "jwt/claims", to: "jwt_header_only#claims"
    post "jwt/login", to: "jwt_header_only#login"
    get "jwt_session/claims", to: "jwt_with_session#claims"
    post "jwt_session/login", to: "jwt_with_session#login"
    get "rescues/:action", controller: "rescues"
    # Catch-all last: exercises ErrorResponses#route_not_found.
    match "*path", to: "errors#route_not_found", via: :all
  end
end
