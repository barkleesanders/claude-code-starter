---
name: dspy-ruby
user-invocable: true
description: This skill should be used when working with DSPy.rb, a Ruby framework for building type-safe, composable LLM applications. Use this when implementing predictable AI features, creating LLM signatures and modules, configuring language model providers (OpenAI, Anthropic, Gemini, Ollama), building agent systems with tools, optimizing prompts, or testing LLM-powered functionality in Ruby applications.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
model: inherit
---

# DSPy.rb Expert

## Overview

DSPy.rb is a Ruby framework that enables developers to **program LLMs, not prompt them**. Instead of manually crafting prompts, define application requirements through type-safe, composable modules that can be tested, optimized, and version-controlled like regular code.

## Mode Detection

Determine what the user needs, then read ONLY the relevant reference files before proceeding.

| User Intent | Reference Files to Read |
|-------------|------------------------|
| Signatures, modules, predictors, type safety | `core-concepts.md` |
| LLM provider setup, API keys, configuration | `providers.md` |
| Testing, optimization, observability | `optimization.md` |
| Getting started, Rails integration | `quickstart.md` |
| Common patterns, agents, pipelines, vision | `patterns.md` |

All reference files are in `~/.claude/skills/dspy-ruby/references/`.

---

## Core Capabilities (Quick Reference)

### 1. Type-Safe Signatures

```ruby
class EmailClassificationSignature < DSPy::Signature
  description "Classify customer support emails"

  input do
    const :email_subject, String
    const :email_body, String
  end

  output do
    const :category, T.enum(["Technical", "Billing", "General"])
    const :priority, T.enum(["Low", "Medium", "High"])
  end
end
```

**Best practices**: Clear descriptions, enums for constrained outputs, `desc:` parameter for fields, specific types over generic String. Full docs: `core-concepts.md`.

### 2. Composable Modules

```ruby
class EmailProcessor < DSPy::Module
  def initialize
    super
    @classifier = DSPy::Predict.new(EmailClassificationSignature)
  end

  def forward(email_subject:, email_body:)
    @classifier.forward(email_subject: email_subject, email_body: email_body)
  end
end
```

Chain modules for complex workflows. Full docs: `core-concepts.md`.

### 3. Predictor Types

| Predictor | Use For | Key Feature |
|-----------|---------|-------------|
| **Predict** | Simple tasks, classification, extraction | Basic type-safe inference |
| **ChainOfThought** | Complex reasoning, analysis | Automatic reasoning step |
| **ReAct** | Tasks requiring external tools | Iterative tool-using agent |
| **CodeAct** | Tasks best solved with code | Dynamic code generation (`dspy-code_act` gem) |

Full docs: `core-concepts.md`.

### 4. LLM Provider Configuration

```ruby
# OpenAI
DSPy.configure { |c| c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }

# Anthropic Claude
DSPy.configure { |c| c.lm = DSPy::LM.new('anthropic/claude-3-5-sonnet-20241022', api_key: ENV['ANTHROPIC_API_KEY']) }

# Google Gemini
DSPy.configure { |c| c.lm = DSPy::LM.new('gemini/gemini-1.5-pro', api_key: ENV['GOOGLE_API_KEY']) }

# Local Ollama (free, private)
DSPy.configure { |c| c.lm = DSPy::LM.new('ollama/llama3.1') }
```

**Provider compatibility matrix**:

| Feature | OpenAI | Anthropic | Gemini | Ollama |
|---------|--------|-----------|--------|--------|
| Structured Output | yes | yes | yes | yes |
| Vision (Images) | yes | yes | yes | limited |
| Image URLs | yes | no | no | no |
| Tool Calling | yes | yes | yes | varies |

**Cost optimization**: Dev = Ollama/gpt-4o-mini, Test = gpt-4o-mini (temp=0), Prod simple = gpt-4o-mini/haiku/flash, Prod complex = gpt-4o/sonnet/pro. Full docs: `providers.md`.

### 5. Testing

```ruby
RSpec.describe EmailClassifier do
  before do
    DSPy.configure { |c| c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }
  end

  it 'classifies technical emails correctly' do
    result = EmailClassifier.new.forward(email_subject: "Can't log in", email_body: "Unable to access account")
    expect(result[:category]).to eq('Technical')
  end
end
```

Full docs: `optimization.md`.

---

## Reference Files Index

| File | Content |
|------|---------|
| `core-concepts.md` | Signatures, modules, predictors, multimodal support, best practices |
| `providers.md` | All LLM provider configs, compatibility matrix, cost optimization, troubleshooting |
| `optimization.md` | Testing patterns, MIPROv2 optimization, observability, monitoring |
| `quickstart.md` | Step-by-step new project setup, Rails integration |
| `patterns.md` | Multi-step pipelines, agents with tools, conditional routing, retry/fallback, vision, observability |

### Assets (templates for quick starts)

- `assets/signature-template.rb` -- Examples of signatures including basic, vision, sentiment, code gen
- `assets/module-template.rb` -- Module patterns including pipelines, agents, error handling, caching
- `assets/config-template.rb` -- Configuration for all providers, environments, observability, production

## When to Use This Skill

- Implementing LLM-powered features in Ruby applications
- Creating type-safe interfaces for AI operations
- Building agent systems with tool usage
- Setting up or troubleshooting LLM providers
- Optimizing prompts and improving accuracy
- Testing LLM functionality
- Adding observability to AI applications
- Converting from manual prompt engineering to programmatic approach
- Debugging DSPy.rb code or configuration issues
