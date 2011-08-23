module SpreedlyCore
  # Abstract class for all the different spreedly core transactions
  class Transaction < Base
    attr_reader(:amount, :on_test_gateway, :created_at, :updated_at, :currency_code,
                :succeeded, :token, :message, :transaction_type, :gateway_token,
                :response)
    alias :succeeded? :succeeded

    # Breaks enacapsulation a bit, but allow subclasses to register the 'transaction_type'
    # they handle.
    def self.handles(transaction_type)
      @@transaction_type_to_class ||= {}
      @@transaction_type_to_class[transaction_type] = self
    end

    # Lookup the transaction by its token. Returns the correct subclass
    def self.find(token)
      return nil if token.nil? 
      verify_get("/transactions/#{token}.xml") do |response|
        attrs = response.parsed_response["transaction"]
        klass = @@transaction_type_to_class[attrs["transaction_type"]] || self
        klass.new(attrs)
      end
    end
  end

  class RetainTransaction < Transaction
    handles "RetainPaymentMethod"
    attr_reader :payment_method
    
    def initialize(attrs={})
      @payment_method = PaymentMethod.new(attrs.delete("payment_method") || {})
      super(attrs)
    end
  end
  class RedactTransaction < Transaction
    handles "RedactPaymentMethod"
    attr_reader :payment_method
    
    def initialize(attrs={})
      @payment_method = PaymentMethod.new(attrs.delete("payment_method") || {})
      super(attrs)
    end
  end
  
  module NullifiableTransaction
    # Void is used to cancel out authorizations and, with some gateways, to
    # cancel actual payment transactions within the first 24 hours
    def void
      self.class.verify_post("/transactions/#{token}/void.xml") do |response|
        VoidedTransaction.new(response.parsed_response["transaction"])
      end      
    end

    # Credit amount. If amount is nil, then credit the entire previous purchase
    # or captured amount 
    def credit(amount=nil)
      body = if amount.nil? 
               {}
             else
               {:transaction => {:amount => amount}}
             end
      self.class.verify_post("/transactions/#{token}/credit.xml",
                             :body => body) do |response|
        CreditTransaction.new(response.parsed_response["transaction"])
      end
    end
  end

  class AuthorizeTransaction < Transaction
    handles "Authorization"
    attr_reader :payment_method
    
    def initialize(attrs={})
      @payment_method = PaymentMethod.new(attrs.delete("payment_method") || {})
      @response = Response.new(attrs.delete("response") || {})
      super(attrs)
    end

    # Capture the previously authorized payment. If the amount is nil, the
    # captured amount will the amount from the original authorization. Some
    # gateways support partial captures which can be done by specifiying an
    # amount
    def capture(amount=nil)
      body = if amount.nil?
               {}
             else
               {:transaction => {:amount => amount}}
             end
      self.class.verify_post("/transactions/#{token}/capture.xml",
                            :body => body) do |response|
        CaptureTransaction.new(response.parsed_response["transaction"])
      end
    end
  end

  class PurchaseTransaction < Transaction
    include NullifiableTransaction

    handles "Purchase"
    attr_reader :payment_method

    def initialize(attrs={})
      @payment_method = PaymentMethod.new(attrs.delete("payment_method") || {})
      @response = Response.new(attrs.delete("response") || {})
      super(attrs)
    end
  end

  class CaptureTransaction < Transaction
    include NullifiableTransaction

    handles "Capture"
    attr_reader :reference_token
  end

  class VoidedTransaction < Transaction
    handles "Void"
    attr_reader :reference_token
  end

  class CreditTransaction < Transaction
    handles "Credit"
    attr_reader :reference_token
  end
  
end
