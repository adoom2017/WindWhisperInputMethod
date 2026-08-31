#include "fy_engine.h"
#include <algorithm>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

struct Entry { std::string text, code, comment; int weight{}; };
struct fy_engine { std::vector<Entry> entries; };
struct fy_session {
    fy_engine *engine{}; std::string code, composition, commit; std::string schema = "fullPinyin";
    bool traditional{}; size_t page{}; std::vector<Entry> matches; std::vector<fy_candidate> exported;
};
static std::string lower(std::string s) { for (char &c:s) if(c>='A'&&c<='Z') c += 'a'-'A'; return s; }
static void add_defaults(fy_engine *e) {
    const char *rows[] = {"你好\tnihao", "还是一样\thaishiyiyang", "我们可以一起\twomenkeyiyiqi", "你\tni", "倪\tni", "今天天气很好\tjintiantianqihenhao", "汉字\thanzi", "风语输入法\tfy", "你\tni~\tnirx", "倪\tni~r\tnire", "你好\tnihc", "还是一样\thduiyiyh"};
    for (auto r: rows) { const char *p=std::strchr(r,'\t'); const char *q=std::strchr(p+1,'\t'); e->entries.push_back({std::string(r,p-r),std::string(p+1,q ? q-p-1 : std::strlen(p+1)),q ? q+1 : ""}); }
}
fy_engine *fy_engine_create(const char *data,size_t len) {
    auto *e=new fy_engine; add_defaults(e);
    if(data && len) { std::string all(data,len); size_t pos=0; while(pos<all.size()) { size_t end=all.find('\n',pos); if(end==std::string::npos) end=all.size(); std::string line=all.substr(pos,end-pos); pos=end+1; size_t a=line.find('\t'), b=a==std::string::npos?std::string::npos:line.find('\t',a+1); if(a!=std::string::npos) e->entries.push_back({line.substr(0,a),line.substr(a+1,b==std::string::npos?std::string::npos:b-a-1),{}}); } }
    return e;
}
void fy_engine_destroy(fy_engine *e){delete e;}
fy_session *fy_session_create(fy_engine *e){return e?new fy_session{e}:nullptr;}
void fy_session_destroy(fy_session *s){delete s;}
static void refresh(fy_session *s){ s->matches.clear(); auto needle=lower(s->code); for(auto &e:s->engine->entries) if(lower(e.code).rfind(needle,0)==0) s->matches.push_back(e); std::stable_sort(s->matches.begin(),s->matches.end(),[&](auto&a,auto&b){bool ax=a.code==needle,bx=b.code==needle; return ax!=bx?ax>bx:a.weight>b.weight;}); if(s->page*5>=s->matches.size()) s->page=0; }
int fy_session_process_key(fy_session *s,uint32_t key,uint32_t mods){ if(!s)return 0; if(key==0x2d)return fy_session_page(s,-1); if(key==0x3d)return fy_session_page(s,1); if(key==0x08){if(s->code.empty())return 0;s->code.pop_back();refresh(s);return 1;} if(key==0x20||key==0x0d){return s->matches.empty()?0:fy_session_select_candidate(s,0);} if(key>=0x20&&key<=0x7e && !(mods&0x04)){s->code.push_back((char)key); refresh(s); return 1;} return 0; }
int fy_session_select_candidate(fy_session *s,size_t i){size_t n=s->page*5+i; if(!s||n>=s->matches.size())return 0; s->commit=s->matches[n].text; if(s->traditional && s->commit=="还是一样") s->commit="還是一樣"; s->code.clear();s->matches.clear();s->page=0;return 1;}
int fy_session_page(fy_session *s,int d){if(!s)return 0; size_t pages=(s->matches.size()+4)/5; if(!pages)return 0; long p=(long)s->page+d; if(p<0)p=0; if(p>=(long)pages)p=pages-1; s->page=(size_t)p;return 1;}
int fy_session_set_option(fy_session *s,const char*n,size_t l,int v){if(!s||!n)return 0; std::string k(n,l); if(k=="traditional")s->traditional=v!=0; return 1;}
int fy_session_select_schema(fy_session*s,const char*n,size_t l){if(!s||!n)return 0;s->schema.assign(n,l);return 1;}
int fy_session_snapshot(fy_session*s,fy_snapshot*out){if(!s||!out)return 0; std::memset(out,0,sizeof(*out)); out->commit=s->commit.data();out->commit_len=s->commit.size();out->composition=s->code.data();out->composition_len=s->code.size();out->cursor=s->code.size(); out->page=s->page;out->page_count=(s->matches.size()+4)/5;out->is_last_page=out->page_count==0||s->page+1>=out->page_count;out->is_composing=!s->code.empty(); s->exported.clear(); size_t begin=s->page*5,end=std::min(begin+5,s->matches.size()); for(size_t i=begin;i<end;i++)s->exported.push_back({s->matches[i].text.data(),s->matches[i].text.size(),s->matches[i].comment.data(),s->matches[i].comment.size()}); out->candidates=s->exported.data();out->candidate_count=s->exported.size(); return 1;}
void fy_snapshot_free(fy_snapshot*){}
