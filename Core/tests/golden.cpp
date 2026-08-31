#include "fy_engine.h"
#include <cassert>
#include <cstring>
#include <iostream>
static void type(fy_session*s,const char*t){for(;*t;t++)assert(fy_session_process_key(s,(unsigned char)*t,0));}
int main(){auto*e=fy_engine_create(nullptr,0);auto*s=fy_session_create(e); for(auto x:{"nihao","haishiyiyang","womenkeyiyiqi"}){type(s,x);fy_snapshot q{};assert(fy_session_snapshot(s,&q)&&q.candidate_count);assert(fy_session_select_candidate(s,0));} type(s,"ni~");fy_snapshot q{};fy_session_snapshot(s,&q);assert(q.candidate_count&&q.candidates[0].comment_len==4);fy_session_destroy(s);s=fy_session_create(e);type(s,"haishiyiyang");fy_session_set_option(s,"traditional",11,1);assert(fy_session_select_candidate(s,0));fy_session_snapshot(s,&q);assert(q.commit_len==12);fy_session_destroy(s);fy_engine_destroy(e);std::cout<<"cross-platform golden tests passed\n";}
