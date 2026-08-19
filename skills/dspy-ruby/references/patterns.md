# Common Patterns

## Pattern: Multi-Step Analysis Pipeline

```ruby
class AnalysisPipeline < DSPy::Module
  def initialize
    super
    @extract = DSPy::Predict.new(ExtractSignature)
    @analyze = DSPy::ChainOfThought.new(AnalyzeSignature)
    @summarize = DSPy::Predict.new(SummarizeSignature)
  end

  def forward(text:)
    extracted = @extract.forward(text: text)
    analyzed = @analyze.forward(data: extracted[:data])
    @summarize.forward(analysis: analyzed[:result])
  end
end
```

## Pattern: Agent with Tools

```ruby
class ResearchAgent < DSPy::Module
  def initialize
    super
    @agent = DSPy::ReAct.new(
      ResearchSignature,
      tools: [
        WebSearchTool.new,
        DatabaseQueryTool.new,
        SummarizerTool.new
      ],
      max_iterations: 10
    )
  end

  def forward(question:)
    @agent.forward(question: question)
  end
end

class WebSearchTool < DSPy::Tool
  def call(query:)
    results = perform_search(query)
    { results: results }
  end
end
```

## Pattern: Conditional Routing

```ruby
class SmartRouter < DSPy::Module
  def initialize
    super
    @classifier = DSPy::Predict.new(ClassifySignature)
    @simple_handler = SimpleModule.new
    @complex_handler = ComplexModule.new
  end

  def forward(input:)
    classification = @classifier.forward(text: input)

    if classification[:complexity] == 'Simple'
      @simple_handler.forward(input: input)
    else
      @complex_handler.forward(input: input)
    end
  end
end
```

## Pattern: Retry with Fallback

```ruby
class RobustModule < DSPy::Module
  MAX_RETRIES = 3

  def forward(input, retry_count: 0)
    begin
      @predictor.forward(input)
    rescue DSPy::ValidationError => e
      if retry_count < MAX_RETRIES
        sleep(2 ** retry_count)
        forward(input, retry_count: retry_count + 1)
      else
        # Fallback to default or raise
        raise
      end
    end
  end
end
```

## Pattern: Multimodal / Vision

Process images alongside text using the unified `DSPy::Image` interface.

```ruby
class VisionSignature < DSPy::Signature
  description "Analyze image and answer questions"

  input do
    const :image, DSPy::Image
    const :question, String
  end

  output do
    const :answer, String
  end
end

predictor = DSPy::Predict.new(VisionSignature)
result = predictor.forward(
  image: DSPy::Image.from_file("path/to/image.jpg"),
  question: "What objects are visible?"
)
```

**Image loading methods**:
```ruby
# From file
DSPy::Image.from_file("path/to/image.jpg")

# From URL (OpenAI only)
DSPy::Image.from_url("https://example.com/image.jpg")

# From base64
DSPy::Image.from_base64(base64_data, mime_type: "image/jpeg")
```

**Provider support**:
- OpenAI: Full support including URLs
- Anthropic, Gemini: Base64 or file loading only
- Ollama: Limited multimodal depending on model

## Pattern: Observability & Monitoring

**OpenTelemetry integration**:
```ruby
require 'opentelemetry/sdk'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'my-dspy-app'
  c.use_all
end

# DSPy automatically creates traces
```

**Langfuse tracing**:
```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY'])

  c.langfuse = {
    public_key: ENV['LANGFUSE_PUBLIC_KEY'],
    secret_key: ENV['LANGFUSE_SECRET_KEY']
  }
end
```
