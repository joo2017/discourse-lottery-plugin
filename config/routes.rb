# frozen_string_literal: true

DiscourseLottery::Engine.routes.draw do
  get '/stats' => 'lottery#stats'
  
  resources :lotteries, path: '/', only: [:show] do
    member do
      get :participants
      post :cancel
    end
  end
end
