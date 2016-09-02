class String
  def camelcase
    self.gsub(/(?:^|_)(\w)/){ $1.upcase }
  end
end
