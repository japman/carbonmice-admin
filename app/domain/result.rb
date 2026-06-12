# Shared return value for use cases: expected failures are values, not exceptions.
class Result
  attr_reader :value, :error

  def self.success(value = nil) = new(success: true, value: value)
  def self.failure(error) = new(success: false, error: error)

  def initialize(success:, value: nil, error: nil)
    @success, @value, @error = success, value, error
  end

  def success? = @success
  def failure? = !@success
end
