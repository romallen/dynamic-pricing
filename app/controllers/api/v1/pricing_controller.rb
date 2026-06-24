class Api::V1::PricingController < ApplicationController
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS  = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS   = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  PARAMETER_ALLOWLISTS = [
    { param: :period, valid_values: VALID_PERIODS },
    { param: :hotel,  valid_values: VALID_HOTELS },
    { param: :room,   valid_values: VALID_ROOMS }
  ].freeze

  before_action :validate_params

  def index
    service = Api::V1::PricingService.new(
      period: params[:period],
      hotel: params[:hotel],
      room: params[:room]
    )
    service.run
    if service.valid?
      render json: { rate: service.result }
    else
      render json: { error: service.errors.join(", ") }, status: :bad_request
    end
  end

  private

  def validate_params
    return render_error("Missing required parameters: period, hotel, room") unless all_params_present?

    PARAMETER_ALLOWLISTS.each do |allowlist|
      param = allowlist[:param]
      valid_values = allowlist[:valid_values]
      next if valid_values.include?(params[param])

      return render_error("Invalid #{param}. Must be one of: #{valid_values.join(', ')}")
    end
  end

  def all_params_present?
    params[:period].present? && params[:hotel].present? && params[:room].present?
  end

  def render_error(message)
    render json: { error: message }, status: :bad_request
  end
end
