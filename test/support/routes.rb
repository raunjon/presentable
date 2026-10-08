# frozen_string_literal: true

Dummy::Application.routes.draw do
  scope defaults: { format: "json" } do
    get "leads/with_metadata", to: "leads#with_metadata"
    get "leads", to: "leads#index"
    get "layered_leads", to: "layered_leads#index"
    get "leads/:id", to: "leads#show"
  end
end
