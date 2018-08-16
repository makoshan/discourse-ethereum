# name: discourse-ethereum
# version: 0.1
# author: ProCourse Team
# url: https://github.com/procourse/discourse-ethereum

enabled_site_setting :discourse_ethereum_enabled
register_asset "stylesheets/common.scss"
register_asset "stylesheets/mobile.scss", :mobile

require_relative "lib/ethereum"

after_initialize {

  load File.expand_path("../jobs/send_tx_details.rb", __FILE__)

  require_dependency "guardian"
  Guardian.class_eval {

    def can_do_eth_transaction?(target_user)
      return false unless authenticated?

      (current_user.id != target_user.id) &&
      eth_enabled_for_user?(current_user) &&
      eth_enabled_for_user?(target_user)
    end

    def eth_enabled_for_user?(user = nil)
      SiteSetting.discourse_ethereum_enabled &&
      user &&
      user.custom_fields["ethereum_address"].present? &&
      (SiteSetting.discourse_ethereum_all_user || user.groups.where(name: SiteSetting.discourse_ethereum_groups.split("|")).exists?)
    end

  }

  add_to_serializer(:user, :can_do_eth_transaction) {
    scope.can_do_eth_transaction?(object)
  }

  %w(user current_user).each do |serializer|
    add_to_serializer(serializer.to_sym, :ethereum_address) {
      object.custom_fields["ethereum_address"].to_s.downcase
    }
  end

  require_dependency "application_controller"
  class ::EthereumController < ::ApplicationController
    requires_plugin("discourse-ethereum")
    before_action :ensure_logged_in

    def send_tx_details
      params.require([:tx_hash, :target_user_id])

      args = {
        hash: params[:tx_hash],
        from_id: current_user.id,
        to_id: params[:target_user_id]
      }

      Jobs.enqueue(:send_tx_details, args)

      render json: success_json
    end
  end

  Discourse::Application.routes.append {

    post "ethereum" => "ethereum#send_tx_details"

  }

}