class Array
  def keys
    map { |k, _v| k }
  end

  def values
    map { |_k, v| v }
  end

  def second
    self[1]
  end
end
