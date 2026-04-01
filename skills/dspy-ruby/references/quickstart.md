# Quick Start Workflow

## For New Projects

1. **Install DSPy.rb and provider gems**:
```bash
gem install dspy dspy-openai  # or dspy-anthropic, dspy-gemini
```

2. **Configure LLM provider** (see `assets/config-template.rb`):
```ruby
require 'dspy'

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY'])
end
```

3. **Create a signature** (see `assets/signature-template.rb`):
```ruby
class MySignature < DSPy::Signature
  description "Clear description of task"

  input do
    const :input_field, String, desc: "Description"
  end

  output do
    const :output_field, String, desc: "Description"
  end
end
```

4. **Create a module** (see `assets/module-template.rb`):
```ruby
class MyModule < DSPy::Module
  def initialize
    super
    @predictor = DSPy::Predict.new(MySignature)
  end

  def forward(input_field:)
    @predictor.forward(input_field: input_field)
  end
end
```

5. **Use the module**:
```ruby
module_instance = MyModule.new
result = module_instance.forward(input_field: "test")
puts result[:output_field]
```

6. **Add tests** (see `references/optimization.md`):
```ruby
RSpec.describe MyModule do
  it 'produces expected output' do
    result = MyModule.new.forward(input_field: "test")
    expect(result[:output_field]).to be_a(String)
  end
end
```

## For Rails Applications

1. **Add to Gemfile**:
```ruby
gem 'dspy'
gem 'dspy-openai'  # or other provider
```

2. **Create initializer** at `config/initializers/dspy.rb` (see `assets/config-template.rb` for full example):
```ruby
require 'dspy'

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY'])
end
```

3. **Create modules in** `app/llm/` directory:
```ruby
# app/llm/email_classifier.rb
class EmailClassifier < DSPy::Module
  # Implementation here
end
```

4. **Use in controllers/services**:
```ruby
class EmailsController < ApplicationController
  def classify
    classifier = EmailClassifier.new
    result = classifier.forward(
      email_subject: params[:subject],
      email_body: params[:body]
    )
    render json: result
  end
end
```
