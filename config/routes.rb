# frozen_string_literal: true

OpenProject::Application.routes.draw do
  namespace :mattermost do
    resource :admin_settings, only: %i[show update], controller: "admin_settings"
  end

  resources :projects, only: [] do
    resource :mattermost_settings,
             controller: "mattermost/project_settings",
             only: %i[show update]
  end
end
