class BaseService
  attr_accessor :result

  def valid?
    errors.blank?
  end

  def errors
    @errors ||= []
  end

  private

  def log_event(level, event, **fields)
    Rails.logger.public_send(level, { service: self.class.name.demodulize, event: event }.merge(fields).to_json)
  end
end
