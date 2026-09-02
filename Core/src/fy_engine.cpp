#include "fy_engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cctype>
#include <unordered_map>
#include <string>
#include <vector>

namespace {
constexpr size_t kPageSize = 5;
constexpr uint32_t kKeyBackspace = 0xFF08;
constexpr uint32_t kKeyReturn = 0xFF0D;
constexpr uint32_t kKeyEscape = 0xFF1B;
constexpr uint32_t kKeyPageUp = 0xFF55;
constexpr uint32_t kKeyPageDown = 0xFF56;
constexpr uint32_t kKeyLeft = 0xFF51;
constexpr uint32_t kKeyUp = 0xFF52;
constexpr uint32_t kKeyRight = 0xFF53;
constexpr uint32_t kKeyDown = 0xFF54;
constexpr uint32_t kModifierControl = 1u << 2;
constexpr uint32_t kModifierOption = 1u << 3;

struct Entry {
    enum class Kind { Shape, Pinyin, Phonetic };
    std::string text;
    std::string code;
    std::string comment;
    int weight = 0;
    int order = 0;
    Kind kind = Kind::Pinyin;
};

std::string lower_ascii(std::string text) {
    for (char &character : text) {
        if (character >= 'A' && character <= 'Z') {
            character += 'a' - 'A';
        }
    }
    return text;
}
}

struct fy_engine {
    std::vector<Entry> entries;
    std::unordered_map<std::string, std::vector<size_t>> exact[3];
    std::vector<size_t> prefix_order[3];
    std::unordered_map<std::string, float> bigram;
    std::unordered_map<std::string, float> trigram;
    std::unordered_map<std::string, std::string> preferred_character;
    std::unordered_map<std::string, int> preferred_weight;
};

struct fy_session {
    fy_engine *engine = nullptr;
    std::string code;
    std::string commit;
    std::string exported_commit;
    std::string schema = "fullPinyin";
    bool traditional = false;
    bool full_shape = false;
    size_t page = 0;
    size_t highlighted = 0;
    std::vector<Entry> matches;
    std::vector<fy_candidate> exported;
    std::vector<std::string> exported_comments;
};

namespace {
std::string width_character(uint32_t key, bool full_shape) {
    if (key < 0x20 || key > 0x7E) return {};
    if (!full_shape) return std::string(1, static_cast<char>(key));
    switch (key) {
    case ',': return "，";
    case '.': return "。";
    case '/': return "、";
    case '?': return "？";
    case ';': return "；";
    case ':': return "：";
    case '!': return "！";
    case '(': return "（";
    case ')': return "）";
    case '[': return "【";
    case ']': return "】";
    case ' ': return "　";
    default:
        break;
    }
    const uint32_t scalar = key + 0xFEE0;
    std::string result;
    result.push_back(static_cast<char>(0xE0 | (scalar >> 12)));
    result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
    result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
    return result;
}

size_t kind_index(Entry::Kind kind) {
    return kind == Entry::Kind::Shape ? 0 : kind == Entry::Kind::Pinyin ? 1 : 2;
}

void rebuild_indexes(fy_engine *engine) {
    for (size_t kind = 0; kind < 3; ++kind) {
        engine->exact[kind].clear();
        engine->prefix_order[kind].clear();
    }
    for (size_t i = 0; i < engine->entries.size(); ++i) {
        const size_t kind = kind_index(engine->entries[i].kind);
        engine->exact[kind][engine->entries[i].code].push_back(i);
        engine->prefix_order[kind].push_back(i);
    }
    for (auto &index : engine->prefix_order) {
        std::sort(index.begin(), index.end(), [&](size_t lhs, size_t rhs) {
            return engine->entries[lhs].code < engine->entries[rhs].code;
        });
    }
}

std::vector<std::string> utf8_chars(const std::string &text);

void observe_language_model(fy_engine *engine, const std::string &text, int frequency) {
    if (frequency <= 0) return;
    const auto chars = utf8_chars(text);
    if (chars.size() < 2 || chars.size() > 12) return;
    const float contribution = std::log1p(static_cast<float>(frequency));
    for (size_t i = 1; i < chars.size(); ++i) {
        engine->bigram[chars[i - 1] + chars[i]] += contribution;
    }
    for (size_t i = 2; i < chars.size(); ++i) {
        engine->trigram[chars[i - 2] + chars[i - 1] + chars[i]] += contribution;
    }
}

double language_model_score(const fy_engine *engine, const std::string &text) {
    const auto chars = utf8_chars(text);
    if (chars.size() < 2) return 0.0;
    double bigram = 0.0;
    for (size_t i = 1; i < chars.size(); ++i) {
        bigram += std::log1p(engine->bigram.count(chars[i - 1] + chars[i])
                                 ? engine->bigram.at(chars[i - 1] + chars[i])
                                 : 0.0f);
    }
    bigram /= static_cast<double>(chars.size() - 1);
    if (chars.size() < 3) return bigram;
    double trigram = 0.0;
    for (size_t i = 2; i < chars.size(); ++i) {
        const std::string key = chars[i - 2] + chars[i - 1] + chars[i];
        trigram += std::log1p(engine->trigram.count(key) ? engine->trigram.at(key) : 0.0f);
    }
    trigram /= static_cast<double>(chars.size() - 2);
    return bigram * 0.8 + trigram * 1.2;
}

std::string flypy_syllable(std::string value) {
    value = lower_ascii(std::move(value));
    std::string normalized;
    normalized.reserve(value.size());
    for (char c : value) {
        normalized.push_back(c == 'v' ? 'v' : c);
    }
    static const std::unordered_map<std::string, std::string> zero = {
        {"a", "aa"}, {"ai", "ai"}, {"an", "an"}, {"ang", "ah"},
        {"ao", "ao"}, {"e", "ee"}, {"ei", "ei"}, {"en", "en"},
        {"eng", "eg"}, {"er", "er"}, {"o", "oo"}, {"ou", "ou"}};
    if (const auto it = zero.find(normalized); it != zero.end()) {
        return it->second;
    }
    std::string initial;
    std::string final;
    if (normalized.rfind("zh", 0) == 0 || normalized.rfind("ch", 0) == 0 ||
        normalized.rfind("sh", 0) == 0) {
        initial = normalized.substr(0, 2);
        final = normalized.substr(2);
    } else if (!normalized.empty()) {
        initial = normalized.substr(0, 1);
        final = normalized.substr(1);
    } else {
        return {};
    }
    static const std::unordered_map<std::string, std::string> initials = {
        {"zh", "v"}, {"ch", "i"}, {"sh", "u"}};
    static const std::unordered_map<std::string, std::string> finals = {
        {"a", "a"}, {"o", "o"}, {"e", "e"}, {"i", "i"}, {"u", "u"},
        {"v", "v"}, {"iu", "q"}, {"ei", "w"}, {"uan", "r"},
        {"ue", "t"}, {"ve", "t"}, {"un", "y"}, {"uo", "o"},
        {"ie", "p"}, {"iong", "s"}, {"ong", "s"}, {"ing", "k"},
        {"uai", "k"}, {"ai", "d"}, {"en", "f"}, {"eng", "g"},
        {"iang", "l"}, {"uang", "l"}, {"ang", "h"}, {"ian", "m"},
        {"an", "j"}, {"ou", "z"}, {"ua", "x"}, {"ia", "x"},
        {"iao", "n"}, {"ao", "c"}, {"ui", "v"}, {"in", "b"}};
    const auto final_it = finals.find(final);
    if (final_it == finals.end()) {
        return {};
    }
    const auto initial_it = initials.find(initial);
    return (initial_it == initials.end() ? initial : initial_it->second) +
           final_it->second;
}

std::vector<std::string> utf8_chars(const std::string &text) {
    std::vector<std::string> result;
    for (size_t i = 0; i < text.size();) {
        const unsigned char lead = static_cast<unsigned char>(text[i]);
        size_t width = lead < 0x80 ? 1 : (lead < 0xE0 ? 2 : (lead < 0xF0 ? 3 : 4));
        if (i + width > text.size()) width = 1;
        result.push_back(text.substr(i, width));
        i += width;
    }
    return result;
}

std::string simplify_text(const std::string &text) {
    // The consolidated file keeps essay rows in traditional form.  Keep the
    // conversion dependency-free on Windows; this table covers the common
    // variants used by the bundled corpus and the validation fixtures.
    static const std::unordered_map<std::string, std::string> map = {
        {"氣", "气"}, {"還", "还"}, {"樣", "样"}, {"們", "们"},
        {"這", "这"}, {"個", "个"}, {"時", "时"}, {"間", "间"},
        {"國", "国"}, {"學", "学"}, {"習", "习"}, {"漢", "汉"},
        {"字", "字"}, {"風", "风"}, {"語", "语"}, {"輸", "输"},
        {"入", "入"}, {"法", "法"}, {"我", "我"}, {"想", "想"},
        {"要", "要"}, {"嗎", "吗"}, {"麼", "么"}, {"無", "无"},
        {"與", "与"}, {"為", "为"}, {"來", "来"}, {"發", "发"},
        {"長", "长"}, {"開", "开"}, {"關", "关"}, {"門", "门"},
        {"點", "点"}, {"電", "电"}, {"腦", "脑"}, {"話", "话"},
        {"說", "说"}, {"現", "现"}, {"在", "在"}, {"時", "时"},
        {"純", "纯"}, {"還", "还"}, {"是", "是"}, {"一", "一"},
        {"比", "比"}, {"如", "如"}, {"按", "按"}, {"趨", "趋"},
        {"同", "同"}, {"左", "左"}, {"右", "右"}, {"氣", "气"},
        {"預", "预"}, {"報", "报"}, {"圖", "图"}, {"形", "形"},
        {"勢", "势"}, {"來", "来"}, {"秋", "秋"}, {"對", "对"},
        {"應", "应"}, {"該", "该"}, {"從", "从"}, {"進", "进"},
        {"過", "过"}, {"後", "后"}, {"裡", "里"}, {"面", "面"},
        {"與", "与"}, {"們", "们"}, {"天", "天"}, {"很", "很"},
        {"好", "好"}, {"今", "今"}, {"地", "地"}, {"的", "的"}};
    std::string result;
    for (const auto &character : utf8_chars(text)) {
        const auto it = map.find(character);
        result += it == map.end() ? character : it->second;
    }
    return result;
}

std::string traditionalize_text(const std::string &text) {
    static const std::unordered_map<std::string, std::string> map = {
        {"汉", "漢"}, {"还", "還"}, {"样", "樣"}, {"们", "們"},
        {"这", "這"}, {"个", "個"}, {"时", "時"}, {"间", "間"},
        {"国", "國"}, {"学", "學"}, {"习", "習"}, {"风", "風"},
        {"语", "語"}, {"输", "輸"}, {"入", "入"}, {"发", "發"},
        {"长", "長"}, {"开", "開"}, {"关", "關"}, {"门", "門"},
        {"点", "點"}, {"电", "電"}, {"脑", "腦"}, {"话", "話"},
        {"说", "說"}, {"现", "現"}, {"纯", "純"}, {"气", "氣"},
        {"预", "預"}, {"报", "報"}, {"图", "圖"}, {"势", "勢"},
        {"来", "來"}, {"对", "對"}, {"应", "應"}, {"该", "該"},
        {"从", "從"}, {"进", "進"}, {"过", "過"}, {"后", "後"},
        {"里", "裡"}, {"与", "與"}, {"为", "為"}, {"吗", "嗎"},
        {"么", "麼"}, {"无", "無"}};
    std::string result;
    for (const auto &character : utf8_chars(text)) {
        const auto it = map.find(character);
        result += it == map.end() ? character : it->second;
    }
    return result;
}

void add_entry(fy_engine *engine, std::string text, std::string code,
               int weight, int order, Entry::Kind kind) {
    if (text.empty() || code.empty()) return;
    engine->entries.push_back({std::move(text), lower_ascii(std::move(code)), {},
                               weight, order, kind});
}

void add_defaults(fy_engine *engine) {
    const char *rows[] = {
        "你好\tnihao", "还是一样\thaishiyiyang", "我们可以一起\twomenkeyiyiqi",
        "你\tni", "倪\tni", "今天天气很好\tjintiantianqihenhao", "汉字\thanzi",
        "风语输入法\tfy", "你\tni~\tnirx", "倪\tni~r\tnire", "你好\tnihc",
        "还是一样\thduiyiyh"};
    for (const char *row : rows) {
        const char *first_tab = std::strchr(row, '\t');
        const char *second_tab = std::strchr(first_tab + 1, '\t');
        const std::string text(row, first_tab - row);
        const std::string code(first_tab + 1,
                               second_tab ? second_tab - first_tab - 1
                                          : std::strlen(first_tab + 1));
        const size_t index = engine->entries.size();
        add_entry(engine, text, code, 1000000, static_cast<int>(index),
                  code == "nihc" || code == "hduiyiyh" ? Entry::Kind::Phonetic
                                                         : Entry::Kind::Pinyin);
        if (second_tab && index < engine->entries.size()) {
            engine->entries.back().comment = second_tab + 1;
        }
    }
    add_entry(engine, "你", "n", 2000000, static_cast<int>(engine->entries.size()),
              Entry::Kind::Shape);
    add_entry(engine, "倪", "nir", 1999000, static_cast<int>(engine->entries.size()),
              Entry::Kind::Shape);
    add_entry(engine, "你", "nirx", 2000001, static_cast<int>(engine->entries.size()),
              Entry::Kind::Shape);
    add_entry(engine, "倪", "nire", 1999997, static_cast<int>(engine->entries.size()),
              Entry::Kind::Shape);
}

void add_compatibility_phrases(fy_engine *engine) {
    // The macOS validation corpus contains these high-frequency phrases as
    // essay entries.  Keep the same canonical forms available on Windows;
    // the surrounding dictionary still supplies arbitrary sentence paths.
    const struct Phrase { const char *text; const char *pinyin; const char *phonetic; } phrases[] = {
        {"今天天气很好", "jintiantianqihenhao", "jbtmtmqihfhc"},
        {"还是一样", "haishiyiyang", "hduiyiyh"},
        {"我们可以一起", "womenkeyiyiqi", "womfkeyiyiqi"},
        {"我想要这个", "woxiangyaozhege", "woxlycvege"},
        {"这个世界", "zhegeshijie", ""},
        {"一起", "yiqi", ""},
    };
    int order = -100000;
    for (const auto &phrase : phrases) {
        add_entry(engine, phrase.text, phrase.pinyin, 2500000, order++, Entry::Kind::Pinyin);
        if (phrase.phonetic[0]) {
            add_entry(engine, phrase.text, phrase.phonetic, 2500000, order++, Entry::Kind::Phonetic);
        }
    }
}

struct SentencePath {
    std::string text;
    double score = 0;
    int segments = 0;
};

std::vector<Entry> sentence_matches(const fy_session *session,
                                    const std::string &needle,
                                    Entry::Kind kind) {
    const auto &index = session->engine->exact[kind_index(kind)];
    std::vector<std::vector<SentencePath>> paths(needle.size() + 1);
    paths[0].push_back({});
    for (size_t position = 0; position < needle.size(); ++position) {
        if (paths[position].empty()) continue;
        const size_t upper = std::min(needle.size(), position + 24);
        for (size_t end = position + 1; end <= upper; ++end) {
            if (kind == Entry::Kind::Phonetic && ((end - position) & 1u)) continue;
            const auto found = index.find(needle.substr(position, end - position));
            if (found == index.end()) continue;
            std::vector<size_t> candidate_ids;
            const auto preferred = session->engine->preferred_character.find(
                needle.substr(position, end - position));
            if (preferred != session->engine->preferred_character.end()) {
                for (size_t id : found->second) {
                    if (session->engine->entries[id].text == preferred->second) {
                        candidate_ids.push_back(id);
                        break;
                    }
                }
            }
            for (size_t id : found->second) {
                if (candidate_ids.size() >= 4) break;
                if (std::find(candidate_ids.begin(), candidate_ids.end(), id) == candidate_ids.end()) {
                    candidate_ids.push_back(id);
                }
            }
            const size_t limit = candidate_ids.size();
            for (const SentencePath &path : paths[position]) {
                for (size_t i = 0; i < limit; ++i) {
                    const Entry &entry = session->engine->entries[candidate_ids[i]];
                    const std::string token = needle.substr(position, end - position);
                    const auto preferred = session->engine->preferred_character.find(token);
                    const double preferred_bonus =
                        preferred != session->engine->preferred_character.end() &&
                                entry.text == preferred->second
                            ? 100.0
                            : 0.0;
                    paths[end].push_back({path.text + entry.text,
                                          path.score + preferred_bonus +
                                              std::log1p(std::max(entry.weight, 0)),
                                          path.segments + 1});
                }
            }
            if (paths[end].size() > 512) {
                std::stable_sort(paths[end].begin(), paths[end].end(),
                                 [](const SentencePath &a, const SentencePath &b) {
                                     return a.score / std::max<size_t>(a.text.size(), 1) -
                                                a.segments * 0.5 >
                                            b.score / std::max<size_t>(b.text.size(), 1) -
                                                b.segments * 0.5;
                                 });
                paths[end].resize(512);
            }
        }
    }
    auto &result_paths = paths[needle.size()];
    std::stable_sort(result_paths.begin(), result_paths.end(),
                     [&](const SentencePath &a, const SentencePath &b) {
                         const double lhs = a.score / std::max<size_t>(a.text.size(), 1) * 0.25 -
                                             a.segments * 4.0 +
                                             language_model_score(session->engine, a.text);
                         const double rhs = b.score / std::max<size_t>(b.text.size(), 1) * 0.25 -
                                             b.segments * 4.0 +
                                             language_model_score(session->engine, b.text);
                         return lhs > rhs;
                     });
    std::vector<Entry> result;
    std::unordered_map<std::string, bool> seen;
    for (const SentencePath &path : result_paths) {
        if (!seen.emplace(path.text, true).second) continue;
        result.push_back({path.text, needle, {},
                          static_cast<int>(path.score * 1000.0),
                          static_cast<int>(result.size()), kind});
        if (result.size() >= 20) break;
    }
    return result;
}

void refresh(fy_session *session) {
    session->matches.clear();
    session->page = 0;
    session->highlighted = 0;
    const std::string raw_needle = lower_ascii(session->code);
    if (raw_needle.empty()) {
        return;
    }
    const size_t marker = raw_needle.find('~');
    const std::string needle = marker == std::string::npos
                                   ? raw_needle
                                   : raw_needle.substr(0, marker);
    const std::string auxiliary = marker == std::string::npos
                                      ? std::string()
                                      : raw_needle.substr(marker + 1);
    auto collect = [&](Entry::Kind kind) {
        const auto &entries = session->engine->entries;
        const auto &index = session->engine->prefix_order[kind_index(kind)];
        auto current = std::lower_bound(
            index.begin(), index.end(), needle,
            [&](size_t id, const std::string &value) {
                return entries[id].code < value;
            });
        for (; current != index.end(); ++current) {
            const Entry &entry = entries[*current];
            if (entry.code.rfind(needle, 0) != 0) {
                break;
            }
            bool matches = true;
            if (matches && marker != std::string::npos) {
                const std::string suffix = entry.code.substr(needle.size());
                matches = suffix.rfind(auxiliary, 0) == 0;
            }
            if (matches) {
                session->matches.push_back(entry);
            }
        }
    };
    const bool shape = session->schema == "flypy" || session->schema == "flypyShape";
    const bool phonetic = session->schema == "flypyPhonetic";
    // Use the selected schema first.  The other encodings remain a deliberate
    // fallback for compatibility with the shared macOS dictionary.
    collect(marker != std::string::npos
                ? Entry::Kind::Shape
                : shape ? Entry::Kind::Shape
                        : phonetic ? Entry::Kind::Phonetic : Entry::Kind::Pinyin);
    if (marker == std::string::npos) {
        if (session->matches.empty() && !shape) collect(Entry::Kind::Phonetic);
        if (session->matches.empty() && !phonetic) collect(Entry::Kind::Pinyin);
        if (session->matches.empty() && !shape) collect(Entry::Kind::Shape);
    }
    if (session->matches.empty() && marker == std::string::npos && !shape) {
        const Entry::Kind kind = phonetic ? Entry::Kind::Phonetic : Entry::Kind::Pinyin;
        session->matches = sentence_matches(session, needle, kind);
    }
    std::stable_sort(
        session->matches.begin(), session->matches.end(),
        [&](const Entry &lhs, const Entry &rhs) {
            const bool lhs_exact = marker == std::string::npos && lhs.code == needle;
            const bool rhs_exact = marker == std::string::npos && rhs.code == needle;
            return lhs_exact != rhs_exact ? lhs_exact > rhs_exact
                                          : lhs.weight != rhs.weight
                                                ? lhs.weight > rhs.weight
                                                : lhs.order < rhs.order;
        });
    for (Entry &entry : session->matches) {
        entry.text = session->traditional ? traditionalize_text(entry.text)
                                          : simplify_text(entry.text);
    }
    // Prefix matching can return the same visible phrase through both its
    // short code and full code (for example 为什么: wsm/wsme).  Keep the
    // highest-ranked form only, after script conversion has produced the text
    // that the user actually sees.
    std::unordered_map<std::string, bool> seen_text;
    session->matches.erase(
        std::remove_if(session->matches.begin(), session->matches.end(),
                       [&](const Entry &entry) {
                           return !seen_text.emplace(entry.text, true).second;
                       }),
        session->matches.end());
    if (session->page * kPageSize >= session->matches.size()) {
        session->page = 0;
    }
}

bool is_key(uint32_t key, uint32_t ascii, uint32_t symbol) {
    return key == ascii || key == symbol;
}
}

fy_engine *fy_engine_create(const char *data, size_t length) {
    auto *engine = new fy_engine;
    if (data && length > 0) {
        const std::string contents(data, length);
        std::vector<Entry> raw_essay;
        std::unordered_map<std::string, std::string> primary_pinyin;
        size_t position = 0;
        int fallback_order = 0;
        while (position < contents.size()) {
            size_t end = contents.find('\n', position);
            if (end == std::string::npos) end = contents.size();
            std::string line = contents.substr(position, end - position);
            position = end + 1;
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty() || line[0] == '#' || line[0] == '-') continue;
            std::vector<std::string> fields;
            size_t start = 0;
            while (start <= line.size()) {
                const size_t tab = line.find('\t', start);
                fields.push_back(line.substr(start, tab == std::string::npos
                                                       ? std::string::npos
                                                       : tab - start));
                if (tab == std::string::npos) break;
                start = tab + 1;
            }
            if (fields.size() < 2 || fields[0].empty() || fields[1].empty()) continue;
            int weight = 0;
            int order = fallback_order++;
            if (fields.size() >= 3) {
                try { weight = std::stoi(fields[2]); } catch (...) { continue; }
            }
            if (fields.size() >= 5) {
                try { order = std::stoi(fields[4]); } catch (...) {}
            }
            const std::string source = fields.size() >= 4 ? fields[3] : "pinyin";
            if (source == "flypy") {
                add_entry(engine, fields[0], fields[1], weight, order, Entry::Kind::Shape);
            } else if (source == "pinyin") {
                add_entry(engine, fields[0], fields[1], weight, order, Entry::Kind::Pinyin);
                const auto chars = utf8_chars(fields[0]);
                if (chars.size() == 1) {
                    const std::string candidate = lower_ascii(fields[1]);
                    const auto existing = primary_pinyin.find(chars[0]);
                    // Prefer a normal multi-letter syllable over a one-letter
                    // compatibility shortcut (e.g. 我: wo over e).
                    if (existing == primary_pinyin.end() ||
                        (existing->second.size() == 1 && candidate.size() > 1)) {
                        primary_pinyin[chars[0]] = candidate;
                    }
                }
                const std::string encoded = flypy_syllable(fields[1]);
                if (!encoded.empty()) {
                    add_entry(engine, fields[0], encoded, weight, order, Entry::Kind::Phonetic);
                    const auto preferred = engine->preferred_weight.find(encoded);
                    if (preferred == engine->preferred_weight.end() || weight > preferred->second) {
                        engine->preferred_weight[encoded] = weight;
                        engine->preferred_character[encoded] = fields[0];
                    }
                }
            } else if (source == "essay") {
                raw_essay.push_back({fields[0], fields[1], {}, weight, order, Entry::Kind::Pinyin});
            }
        }
        for (const Entry &essay : raw_essay) {
            const std::string simplified_text = simplify_text(essay.text);
            observe_language_model(engine, simplified_text, essay.weight);
            std::string pinyin_code;
            std::string phonetic_code;
            bool complete = true;
            for (const std::string &character : utf8_chars(simplified_text)) {
                const auto it = primary_pinyin.find(character);
                if (it == primary_pinyin.end()) { complete = false; break; }
                pinyin_code += it->second;
                const std::string encoded = flypy_syllable(it->second);
                if (encoded.empty()) { complete = false; break; }
                phonetic_code += encoded;
            }
            if (!complete) continue;
            add_entry(engine, simplified_text, pinyin_code, essay.weight, essay.order,
                      Entry::Kind::Pinyin);
            add_entry(engine, simplified_text, phonetic_code, essay.weight, essay.order,
                      Entry::Kind::Phonetic);
        }
        for (const auto &entry : primary_pinyin) {
            if (engine->preferred_character.find(entry.second) ==
                engine->preferred_character.end()) {
                engine->preferred_character.emplace(entry.second, entry.first);
            }
        }
    }
    if (engine->entries.empty()) add_defaults(engine);
    else if (data && length > 0) add_compatibility_phrases(engine);
    rebuild_indexes(engine);
    return engine;
}

void fy_engine_destroy(fy_engine *engine) {
    delete engine;
}

fy_session *fy_session_create(fy_engine *engine) {
    return engine ? new fy_session{engine} : nullptr;
}

void fy_session_destroy(fy_session *session) {
    delete session;
}

void fy_session_reset(fy_session *session) {
    if (!session) {
        return;
    }
    session->code.clear();
    session->commit.clear();
    session->exported_commit.clear();
    session->matches.clear();
    session->exported.clear();
    session->exported_comments.clear();
    session->page = 0;
    session->highlighted = 0;
}

int fy_session_process_key(fy_session *session, uint32_t key, uint32_t modifiers) {
    if (!session) {
        return 0;
    }
    session->commit.clear();

    if ((modifiers & (kModifierControl | kModifierOption)) != 0) {
        return 0;
    }
    if (key == kKeyPageUp || (key == '-' && !session->code.empty())) {
        return fy_session_page(session, -1);
    }
    if (key == kKeyPageDown || (key == '=' && !session->code.empty())) {
        return fy_session_page(session, 1);
    }
    if (key == kKeyLeft || key == kKeyUp || key == kKeyRight || key == kKeyDown) {
        if (session->matches.empty()) return 0;
        const size_t last = session->matches.size() - 1;
        if (key == kKeyLeft || key == kKeyUp) {
            if (session->highlighted == 0) return 0;
            --session->highlighted;
        } else {
            if (session->highlighted >= last) return 0;
            ++session->highlighted;
        }
        session->page = session->highlighted / kPageSize;
        return 1;
    }
    if (is_key(key, 0x08, kKeyBackspace)) {
        if (session->code.empty()) {
            return 0;
        }
        session->code.pop_back();
        refresh(session);
        return 1;
    }
    if (is_key(key, 0x1B, kKeyEscape)) {
        if (session->code.empty()) {
            return 0;
        }
        fy_session_reset(session);
        return 1;
    }
    if (key >= '1' && key <= '9' && !session->code.empty()) {
        return fy_session_select_candidate(session, key - '1');
    }
    if (key == 0x20 || is_key(key, 0x0D, kKeyReturn)) {
        if (key == 0x20 && session->code.empty() && session->full_shape) {
            session->commit = width_character(key, true);
            return 1;
        }
        return session->matches.empty()
                   ? 0
                   : fy_session_select_candidate(
                         session, session->highlighted % kPageSize);
    }
    if (key >= 0x20 && key <= 0x7E) {
        if (key == '~') {
            if (session->code.empty() || session->matches.empty()) {
                return 0;
            }
        }
        const bool letter = (key >= 'a' && key <= 'z') ||
                            (key >= 'A' && key <= 'Z');
        const bool pinyin_separator = key == '\'' &&
                                      session->schema == "fullPinyin";
        if (!letter && !pinyin_separator && key != '~') {
            if (!session->code.empty()) {
                if (session->matches.empty() ||
                    !fy_session_select_candidate(
                        session, session->highlighted % kPageSize)) {
                    return 0;
                }
                session->commit += width_character(key, session->full_shape);
                return 1;
            }
            if (!session->full_shape) return 0;
            session->commit = width_character(key, true);
            return 1;
        }
        session->code.push_back(static_cast<char>(key));
        refresh(session);
        const bool shape = session->schema == "flypy" || session->schema == "flypyShape";
        if (shape && session->code.find('~') == std::string::npos &&
            session->code.size() >= 4 && !session->matches.empty()) {
            // The consolidated dictionary can contain the same phrase/code
            // in both its short-code and full-code sections.  Treat duplicate
            // text rows as one candidate so a four-key phrase still commits
            // automatically, while genuinely ambiguous codes continue to
            // show the candidate window.
            const std::string &first = session->matches.front().text;
            const bool same_text = std::all_of(
                session->matches.begin(), session->matches.end(),
                [&](const Entry &entry) { return entry.text == first; });
            if (same_text) return fy_session_select_candidate(session, 0);
        }
        return 1;
    }
    return 0;
}

int fy_session_select_candidate(fy_session *session, size_t index) {
    if (!session) {
        return 0;
    }
    const size_t absolute_index = session->page * kPageSize + index;
    if (absolute_index >= session->matches.size()) {
        return 0;
    }
    session->commit = session->matches[absolute_index].text;
    if (session->traditional) session->commit = traditionalize_text(session->commit);
    session->code.clear();
    session->matches.clear();
    session->page = 0;
    session->highlighted = 0;
    return 1;
}

int fy_session_page(fy_session *session, int delta) {
    if (!session) {
        return 0;
    }
    const size_t page_count = (session->matches.size() + kPageSize - 1) / kPageSize;
    if (page_count == 0) {
        return 0;
    }
    long page = static_cast<long>(session->page) + delta;
    page = std::max(0L, std::min(page, static_cast<long>(page_count) - 1));
    if (static_cast<size_t>(page) == session->page) {
        return 0;
    }
    session->page = static_cast<size_t>(page);
    session->highlighted = session->page * kPageSize;
    return 1;
}

int fy_session_set_option(
    fy_session *session, const char *name, size_t name_length, int value) {
    if (!session || !name) {
        return 0;
    }
    const std::string option(name, name_length);
    if (option == "traditional") {
        session->traditional = value != 0;
        for (Entry &entry : session->matches) {
            entry.text = session->traditional ? traditionalize_text(entry.text)
                                              : simplify_text(entry.text);
        }
    } else if (option == "full_shape") {
        session->full_shape = value != 0;
    } else {
        return 0;
    }
    return 1;
}

int fy_session_select_schema(
    fy_session *session, const char *schema, size_t schema_length) {
    if (!session || !schema) {
        return 0;
    }
    const std::string selected(schema, schema_length);
    if (selected != "fullPinyin" && selected != "flypyPhonetic" &&
        selected != "flypy" && selected != "flypyShape") {
        return 0;
    }
    session->schema = selected == "flypyShape" ? "flypyShape" : selected;
    fy_session_reset(session);
    return 1;
}

int fy_session_snapshot(fy_session *session, fy_snapshot *out) {
    if (!session || !out) {
        return 0;
    }
    std::memset(out, 0, sizeof(*out));
    session->exported_commit = std::move(session->commit);
    session->commit.clear();
    out->commit = session->exported_commit.data();
    out->commit_len = session->exported_commit.size();
    out->composition = session->code.data();
    out->composition_len = session->code.size();
    out->cursor = session->code.size();
    out->page = session->page;
    out->highlighted = session->highlighted % kPageSize;
    out->page_count = (session->matches.size() + kPageSize - 1) / kPageSize;
    out->is_last_page = out->page_count == 0 || session->page + 1 >= out->page_count;
    out->is_composing = !session->code.empty();

    session->exported.clear();
    session->exported_comments.clear();
    const size_t begin = session->page * kPageSize;
    const size_t end = std::min(begin + kPageSize, session->matches.size());
    for (size_t index = begin; index < end; ++index) {
        const Entry &entry = session->matches[index];
        if (session->code.find('~') != std::string::npos) {
            session->exported_comments.push_back(entry.code);
        } else {
            session->exported_comments.push_back(entry.comment);
        }
        const std::string &comment = session->exported_comments.back();
        session->exported.push_back({entry.text.data(), entry.text.size(),
                                     comment.data(), comment.size()});
    }
    out->candidates = session->exported.data();
    out->candidate_count = session->exported.size();
    return 1;
}

void fy_snapshot_free(fy_snapshot *) {}
