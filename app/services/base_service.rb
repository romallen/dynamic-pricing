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
    pairs = fields.map { |k, v| "#{k}=#{v.to_s.inspect}" }
    msg = "[#{self.class.name.demodulize}] event=#{event}"
    msg += " #{pairs.join(' ')}" unless pairs.empty?
    Rails.logger.public_send(level, msg)
  end
end
