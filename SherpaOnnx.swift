/// SherpaOnnx.swift — 裁剪版，只保留 Offline Recognizer (SenseVoice) 所需内容
/// 原始文件: https://github.com/k2-fsa/sherpa-onnx/master/swift-api-examples/SherpaOnnx.swift
/// Copyright (c) 2023 Xiaomi Corporation

import Foundation

func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
  let cs = (s as NSString).utf8String
  return UnsafePointer<Int8>(cs)
}

// MARK: - Feature Config

func sherpaOnnxFeatureConfig(
  sampleRate: Int = 16000,
  featureDim: Int = 80
) -> SherpaOnnxFeatureConfig {
  return SherpaOnnxFeatureConfig(
    sample_rate: Int32(sampleRate),
    feature_dim: Int32(featureDim))
}

// MARK: - Offline Model Config (只保留 SenseVoice 相关)

func sherpaOnnxOfflineTransducerModelConfig(
  encoder: String = "",
  decoder: String = "",
  joiner: String = ""
) -> SherpaOnnxOfflineTransducerModelConfig {
  return SherpaOnnxOfflineTransducerModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    joiner: toCPointer(joiner))
}

func sherpaOnnxOfflineParaformerModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineParaformerModelConfig {
  return SherpaOnnxOfflineParaformerModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineZipformerCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineZipformerCtcModelConfig {
  return SherpaOnnxOfflineZipformerCtcModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineWenetCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineWenetCtcModelConfig {
  return SherpaOnnxOfflineWenetCtcModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineOmnilingualAsrCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineOmnilingualAsrCtcModelConfig {
  return SherpaOnnxOfflineOmnilingualAsrCtcModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineMedAsrCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineMedAsrCtcModelConfig {
  return SherpaOnnxOfflineMedAsrCtcModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineFireRedAsrCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineFireRedAsrCtcModelConfig {
  return SherpaOnnxOfflineFireRedAsrCtcModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineNemoEncDecCtcModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineNemoEncDecCtcModelConfig {
  return SherpaOnnxOfflineNemoEncDecCtcModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineDolphinModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineDolphinModelConfig {
  return SherpaOnnxOfflineDolphinModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineWhisperModelConfig(
  encoder: String = "",
  decoder: String = "",
  language: String = "",
  task: String = "transcribe",
  tailPaddings: Int = -1,
  enableTokenTimestamps: Bool = false,
  enableSegmentTimestamps: Bool = false
) -> SherpaOnnxOfflineWhisperModelConfig {
  return SherpaOnnxOfflineWhisperModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    language: toCPointer(language),
    task: toCPointer(task),
    tail_paddings: Int32(tailPaddings),
    enable_token_timestamps: enableTokenTimestamps ? 1 : 0,
    enable_segment_timestamps: enableSegmentTimestamps ? 1 : 0)
}

func sherpaOnnxOfflineCanaryModelConfig(
  encoder: String = "",
  decoder: String = "",
  srcLang: String = "en",
  tgtLang: String = "en",
  usePnc: Bool = true
) -> SherpaOnnxOfflineCanaryModelConfig {
  return SherpaOnnxOfflineCanaryModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    src_lang: toCPointer(srcLang),
    tgt_lang: toCPointer(tgtLang),
    use_pnc: usePnc ? 1 : 0)
}

func sherpaOnnxOfflineFireRedAsrModelConfig(
  encoder: String = "",
  decoder: String = ""
) -> SherpaOnnxOfflineFireRedAsrModelConfig {
  return SherpaOnnxOfflineFireRedAsrModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder))
}

func sherpaOnnxOfflineMoonshineModelConfig(
  preprocessor: String = "",
  encoder: String = "",
  uncachedDecoder: String = "",
  cachedDecoder: String = "",
  mergedDecoder: String = ""
) -> SherpaOnnxOfflineMoonshineModelConfig {
  return SherpaOnnxOfflineMoonshineModelConfig(
    preprocessor: toCPointer(preprocessor),
    encoder: toCPointer(encoder),
    uncached_decoder: toCPointer(uncachedDecoder),
    cached_decoder: toCPointer(cachedDecoder),
    merged_decoder: toCPointer(mergedDecoder))
}

func sherpaOnnxOfflineTdnnModelConfig(
  model: String = ""
) -> SherpaOnnxOfflineTdnnModelConfig {
  return SherpaOnnxOfflineTdnnModelConfig(
    model: toCPointer(model))
}

func sherpaOnnxOfflineSenseVoiceModelConfig(
  model: String = "",
  language: String = "",
  useInverseTextNormalization: Bool = false
) -> SherpaOnnxOfflineSenseVoiceModelConfig {
  return SherpaOnnxOfflineSenseVoiceModelConfig(
    model: toCPointer(model),
    language: toCPointer(language),
    use_itn: useInverseTextNormalization ? 1 : 0)
}

func sherpaOnnxOfflineLMConfig(
  model: String = "",
  scale: Float = 1.0
) -> SherpaOnnxOfflineLMConfig {
  return SherpaOnnxOfflineLMConfig(
    model: toCPointer(model),
    scale: scale)
}

func sherpaOnnxOfflineFunASRNanoModelConfig(
  encoderAdaptor: String = "",
  llm: String = "",
  embedding: String = "",
  tokenizer: String = "",
  systemPrompt: String = "You are a helpful assistant.",
  userPrompt: String = "语音转写：",
  maxNewTokens: Int = 512,
  temperature: Float = 1e-6,
  topP: Float = 0.8,
  seed: Int = 42,
  language: String = "",
  itn: Bool = true,
  hotwords: String = ""
) -> SherpaOnnxOfflineFunASRNanoModelConfig {
  return SherpaOnnxOfflineFunASRNanoModelConfig(
    encoder_adaptor: toCPointer(encoderAdaptor),
    llm: toCPointer(llm),
    embedding: toCPointer(embedding),
    tokenizer: toCPointer(tokenizer),
    system_prompt: toCPointer(systemPrompt),
    user_prompt: toCPointer(userPrompt),
    max_new_tokens: Int32(maxNewTokens),
    temperature: temperature,
    top_p: topP,
    seed: Int32(seed),
    language: toCPointer(language),
    itn: itn ? 1 : 0,
    hotwords: toCPointer(hotwords))
}

func sherpaOnnxHomophoneReplacerConfig(
  dictDir: String = "",
  lexicon: String = "",
  ruleFsts: String = ""
) -> SherpaOnnxHomophoneReplacerConfig {
  return SherpaOnnxHomophoneReplacerConfig(
    dict_dir: toCPointer(dictDir),
    lexicon: toCPointer(lexicon),
    rule_fsts: toCPointer(ruleFsts))
}

func sherpaOnnxOfflineModelConfig(
  tokens: String,
  transducer: SherpaOnnxOfflineTransducerModelConfig = sherpaOnnxOfflineTransducerModelConfig(),
  paraformer: SherpaOnnxOfflineParaformerModelConfig = sherpaOnnxOfflineParaformerModelConfig(),
  nemoCtc: SherpaOnnxOfflineNemoEncDecCtcModelConfig = sherpaOnnxOfflineNemoEncDecCtcModelConfig(),
  whisper: SherpaOnnxOfflineWhisperModelConfig = sherpaOnnxOfflineWhisperModelConfig(),
  tdnn: SherpaOnnxOfflineTdnnModelConfig = sherpaOnnxOfflineTdnnModelConfig(),
  numThreads: Int = 1,
  provider: String = "cpu",
  debug: Int = 0,
  modelType: String = "",
  modelingUnit: String = "cjkchar",
  bpeVocab: String = "",
  teleSpeechCtc: String = "",
  senseVoice: SherpaOnnxOfflineSenseVoiceModelConfig = sherpaOnnxOfflineSenseVoiceModelConfig(),
  moonshine: SherpaOnnxOfflineMoonshineModelConfig = sherpaOnnxOfflineMoonshineModelConfig(),
  fireRedAsr: SherpaOnnxOfflineFireRedAsrModelConfig = sherpaOnnxOfflineFireRedAsrModelConfig(),
  dolphin: SherpaOnnxOfflineDolphinModelConfig = sherpaOnnxOfflineDolphinModelConfig(),
  zipformerCtc: SherpaOnnxOfflineZipformerCtcModelConfig = sherpaOnnxOfflineZipformerCtcModelConfig(),
  canary: SherpaOnnxOfflineCanaryModelConfig = sherpaOnnxOfflineCanaryModelConfig(),
  wenetCtc: SherpaOnnxOfflineWenetCtcModelConfig = sherpaOnnxOfflineWenetCtcModelConfig(),
  omnilingual: SherpaOnnxOfflineOmnilingualAsrCtcModelConfig = sherpaOnnxOfflineOmnilingualAsrCtcModelConfig(),
  medasr: SherpaOnnxOfflineMedAsrCtcModelConfig = sherpaOnnxOfflineMedAsrCtcModelConfig(),
  funasrNano: SherpaOnnxOfflineFunASRNanoModelConfig = sherpaOnnxOfflineFunASRNanoModelConfig(),
  fireRedAsrCtc: SherpaOnnxOfflineFireRedAsrCtcModelConfig = sherpaOnnxOfflineFireRedAsrCtcModelConfig()
) -> SherpaOnnxOfflineModelConfig {
  return SherpaOnnxOfflineModelConfig(
    transducer: transducer,
    paraformer: paraformer,
    nemo_ctc: nemoCtc,
    whisper: whisper,
    tdnn: tdnn,
    tokens: toCPointer(tokens),
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider),
    model_type: toCPointer(modelType),
    modeling_unit: toCPointer(modelingUnit),
    bpe_vocab: toCPointer(bpeVocab),
    telespeech_ctc: toCPointer(teleSpeechCtc),
    sense_voice: senseVoice,
    moonshine: moonshine,
    fire_red_asr: fireRedAsr,
    dolphin: dolphin,
    zipformer_ctc: zipformerCtc,
    canary: canary,
    wenet_ctc: wenetCtc,
    omnilingual: omnilingual,
    medasr: medasr,
    funasr_nano: funasrNano,
    fire_red_asr_ctc: fireRedAsrCtc)
}

func sherpaOnnxOfflineRecognizerConfig(
  featConfig: SherpaOnnxFeatureConfig,
  modelConfig: SherpaOnnxOfflineModelConfig,
  lmConfig: SherpaOnnxOfflineLMConfig = sherpaOnnxOfflineLMConfig(),
  decodingMethod: String = "greedy_search",
  maxActivePaths: Int = 4,
  hotwordsFile: String = "",
  hotwordsScore: Float = 1.5,
  ruleFsts: String = "",
  ruleFars: String = "",
  blankPenalty: Float = 0.0,
  hr: SherpaOnnxHomophoneReplacerConfig = sherpaOnnxHomophoneReplacerConfig()
) -> SherpaOnnxOfflineRecognizerConfig {
  return SherpaOnnxOfflineRecognizerConfig(
    feat_config: featConfig,
    model_config: modelConfig,
    lm_config: lmConfig,
    decoding_method: toCPointer(decodingMethod),
    max_active_paths: Int32(maxActivePaths),
    hotwords_file: toCPointer(hotwordsFile),
    hotwords_score: hotwordsScore,
    rule_fsts: toCPointer(ruleFsts),
    rule_fars: toCPointer(ruleFars),
    blank_penalty: blankPenalty,
    hr: hr)
}

// MARK: - Offline Recognition Result

class SherpaOnnxOfflineRecongitionResult {
  let result: UnsafePointer<SherpaOnnxOfflineRecognizerResult>

  private lazy var _text: String = {
    guard let cstr = result.pointee.text else { return "" }
    return String(cString: cstr)
  }()

  private lazy var _timestamps: [Float] = {
    guard let p = result.pointee.timestamps else { return [] }
    return (0..<result.pointee.count).map { p[Int($0)] }
  }()

  private lazy var _durations: [Float] = {
    guard let p = result.pointee.durations else { return [] }
    return (0..<result.pointee.count).map { p[Int($0)] }
  }()

  private lazy var _lang: String = {
    guard let cstr = result.pointee.lang else { return "" }
    return String(cString: cstr)
  }()

  private lazy var _emotion: String = {
    guard let cstr = result.pointee.emotion else { return "" }
    return String(cString: cstr)
  }()

  private lazy var _event: String = {
    guard let cstr = result.pointee.event else { return "" }
    return String(cString: cstr)
  }()

  private lazy var _segmentTimestamps: [Float] = {
    guard let p = result.pointee.segment_timestamps else { return [] }
    return (0..<result.pointee.segment_count).map { p[Int($0)] }
  }()

  private lazy var _segmentDurations: [Float] = {
    guard let p = result.pointee.segment_durations else { return [] }
    return (0..<result.pointee.segment_count).map { p[Int($0)] }
  }()

  private lazy var _segmentTexts: [String] = {
    guard let arr = result.pointee.segment_texts_arr else { return [] }
    return (0..<result.pointee.segment_count).compactMap { idx -> String? in
      guard let ptr = arr[Int(idx)] else { return nil }
      return String(cString: ptr)
    }
  }()

  var text: String { _text }
  var count: Int { Int(result.pointee.count) }
  var timestamps: [Float] { _timestamps }
  var durations: [Float] { _durations }
  var lang: String { _lang }
  var emotion: String { _emotion }
  var event: String { _event }
  var segmentCount: Int { Int(result.pointee.segment_count) }
  var segmentTimestamps: [Float] { _segmentTimestamps }
  var segmentDurations: [Float] { _segmentDurations }
  var segmentTexts: [String] { _segmentTexts }

  init(result: UnsafePointer<SherpaOnnxOfflineRecognizerResult>) {
    self.result = result
  }

  deinit {
    SherpaOnnxDestroyOfflineRecognizerResult(result)
  }
}

// MARK: - Offline Stream Wrapper

class SherpaOnnxOfflineStreamWrapper {
  let stream: OpaquePointer

  init(stream: OpaquePointer) {
    self.stream = stream
  }

  deinit {
    SherpaOnnxDestroyOfflineStream(stream)
  }

  func acceptWaveform(samples: [Float], sampleRate: Int = 16_000) {
    SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), samples, Int32(samples.count))
  }
}

// MARK: - Offline Recognizer

class SherpaOnnxOfflineRecognizer {
  private let recognizer: OpaquePointer

  init(config: UnsafePointer<SherpaOnnxOfflineRecognizerConfig>) {
    guard let ptr = SherpaOnnxCreateOfflineRecognizer(config) else {
      fatalError("Failed to create SherpaOnnxOfflineRecognizer")
    }
    self.recognizer = ptr
  }

  deinit {
    SherpaOnnxDestroyOfflineRecognizer(recognizer)
  }

  func decode(samples: [Float], sampleRate: Int = 16_000) -> SherpaOnnxOfflineRecongitionResult {
    let stream = createStream()
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate)
    decode(stream: stream)
    return getResult(stream: stream)
  }

  func createStream() -> SherpaOnnxOfflineStreamWrapper {
    guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
      fatalError("Failed to create offline stream")
    }
    return SherpaOnnxOfflineStreamWrapper(stream: stream)
  }

  func decode(stream: SherpaOnnxOfflineStreamWrapper) {
    SherpaOnnxDecodeOfflineStream(recognizer, stream.stream)
  }

  func getResult(stream: SherpaOnnxOfflineStreamWrapper) -> SherpaOnnxOfflineRecongitionResult {
    guard let resultPtr = SherpaOnnxGetOfflineStreamResult(stream.stream) else {
      fatalError("Failed to get offline recognition result")
    }
    return SherpaOnnxOfflineRecongitionResult(result: resultPtr)
  }
}
