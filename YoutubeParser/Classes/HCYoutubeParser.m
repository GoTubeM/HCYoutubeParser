//
//  HCYoutube.m
//  YoutubeParser
//
//  Created by Simon Andersson on 6/4/12.
//  Copyright (c) 2012 Hiddencode.me. All rights reserved.
//

#import "HCYoutubeParser.h"

#define kYoutubeInfoURL      @"https://www.youtube.com/get_video_info?html5=1&video_id="
#define kYoutubeInfoTokenURL      @"https://www.youtube.com/get_video_info?video_id=%@&t=%@&fmt=140"
#define kYoutubeThumbnailURL @"https://img.youtube.com/vi/%@/%@.jpg"
#define kYoutubeDataURL      @"https://gdata.youtube.com/feeds/api/videos/%@?alt=json"
#define kUserAgent           @"Mozilla/6.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.4 (KHTML, like Gecko) Chrome/78.0.3904.97 Safari/537.4"


@implementation NSString (QueryString)

- (NSString *)stringByDecodingURLFormat {
    NSString *result = [self stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    result = [result stringByRemovingPercentEncoding];
    return result;
}

- (NSMutableDictionary *)dictionaryFromQueryStringComponents {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    for (NSString *keyValue in [self componentsSeparatedByString:@"&"]) {
        NSArray *keyValueArray = [keyValue componentsSeparatedByString:@"="];
        if ([keyValueArray count] < 2) {
            continue;
        }

        NSString *key = [[keyValueArray objectAtIndex:0] stringByDecodingURLFormat];
        NSString *value = [[keyValueArray objectAtIndex:1] stringByDecodingURLFormat];

        NSMutableArray *results = [parameters objectForKey:key];

        if (!results) {
            results = [NSMutableArray arrayWithCapacity:1];
            [parameters setObject:results forKey:key];
        }

        [results addObject:value];
    }

    return parameters;
}

@end

@implementation NSURL (QueryString)

- (NSMutableDictionary *)dictionaryForQueryString {
    return [[self query] dictionaryFromQueryStringComponents];
}

@end

@implementation HCYoutubeParser

+ (NSString *)youtubeIDFromYoutubeURL:(NSURL *)youtubeURL {
    NSString *youtubeID = nil;

    if ([youtubeURL.host isEqualToString:@"youtu.be"]) {
        youtubeID = [[youtubeURL pathComponents] objectAtIndex:1];
    } else if ([youtubeURL.absoluteString rangeOfString:@"www.youtube.com/embed"].location != NSNotFound) {
        youtubeID = [[youtubeURL pathComponents] objectAtIndex:2];
    } else if ([youtubeURL.host isEqualToString:@"youtube.googleapis.com"] ||
               [[youtubeURL.pathComponents firstObject] isEqualToString:@"www.youtube.com"]) {
        youtubeID = [[youtubeURL pathComponents] objectAtIndex:2];
    } else {
        youtubeID = [[[youtubeURL dictionaryForQueryString] objectForKey:@"v"] objectAtIndex:0];
    }
    return youtubeID;
}

+ (NSArray<NSDictionary *> *)audioinfosWithVid:(NSString *)vid token:(NSString *)token {
    __block NSArray<NSDictionary *> *data = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:kYoutubeInfoTokenURL, vid, token]];
    NSLog(@"tokenurl : %@", url);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setHTTPMethod:@"GET"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable datares, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSLog(@"ret :%@", error);
        NSLog(@"respheader: %@", [(NSHTTPURLResponse *)response allHeaderFields]);
        if (!error) {
            NSMutableArray *audios = @[].mutableCopy;

            NSString *responseString = [[NSString alloc] initWithData:datares encoding:NSUTF8StringEncoding];
            NSMutableDictionary *parts = [responseString dictionaryFromQueryStringComponents];
            NSLog(@"second parts :%@", parts);
            NSString *player_response = [parts[@"player_response"] firstObject];
            NSDictionary *player_dict = [NSJSONSerialization JSONObjectWithData:[player_response dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];
            NSDictionary *playstatus = player_dict[@"playabilitStatus"];
            if (![@"ok" isEqualToString:[playstatus[@"status"] lowercaseString]]) {
                dispatch_semaphore_signal(semaphore);
                return ;
            }
            NSArray<NSDictionary *> *formats = player_dict[@"streamingData"][@"adaptiveFormats"];
            [formats enumerateObjectsUsingBlock:^(NSDictionary *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                if ([obj[@"mimeType"] rangeOfString:@"audio/mp4"].length > 0) {
                    NSDictionary *audioinfo = @{
                        @"itag": obj[@"itag"],
                        @"url": obj[@"url"]
                    };
                    [audios addObject:audioinfo];
                }
            }];
            
            data = audios;
            
        }
        
        dispatch_semaphore_signal(semaphore);
    }] resume] ;
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return data;
}

+ (NSArray<NSDictionary *> *)audioM4aWithYoutubeID:(NSString *)vid {
    if (vid) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", kYoutubeInfoURL, vid]];
        NSLog(@"url : %@", url);
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
        [request setHTTPMethod:@"GET"];

        __block NSArray<NSDictionary *> *data = nil;

        __block NSString *token = nil;
        // Lock threads with semaphore
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *_Nullable responseData, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            if (!error) {
                NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];

                NSMutableDictionary *parts = [responseString dictionaryFromQueryStringComponents];

                if (parts) {
                    
                    NSMutableArray *audios = @[].mutableCopy;
                    NSLog(@"parts :%@", parts);
                    NSString *player_response = [parts[@"player_response"] firstObject];
                    if (player_response) {
                        NSLog(@"player_response :%@", player_response);
                       
                        NSError *jerr = nil;
                        NSDictionary *player_dict = [NSJSONSerialization JSONObjectWithData:[player_response dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:&jerr];
                        NSDictionary *playstatus = player_dict[@"playabilityStatus"];
                        if (![@"ok" isEqualToString:[playstatus[@"status"] lowercaseString]]) {
                            
                            token = [parts[@"account_playback_token"] firstObject];
                            dispatch_semaphore_signal(semaphore);
                            return ;
                        }
                                             
                        NSLog(@"streamingData: %@",  player_dict[@"streamingData"]);

                        NSArray<NSDictionary *> *formats = player_dict[@"streamingData"][@"adaptiveFormats"];
                        [formats enumerateObjectsUsingBlock:^(NSDictionary *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                            if ([obj[@"mimeType"] rangeOfString:@"audio/mp4"].length > 0) {
                                NSDictionary *audioinfo = @{
                                        @"itag": obj[@"itag"],
                                        @"url": obj[@"url"]
                                };
                                [audios addObject:audioinfo];
                            }
                        }];
                    }


                    data = audios;
                }
            }
            dispatch_semaphore_signal(semaphore);
        }] resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        if (token) {
            data = [self.class audioinfosWithVid:vid token:token];
        }
        
        return data;
    }
    return nil;
}



+ (NSDictionary *)h264videosWithYoutubeID:(NSString *)youtubeID {
    if (youtubeID) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", kYoutubeInfoURL, youtubeID]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
        [request setHTTPMethod:@"GET"];

        __block NSDictionary *data = nil;

        // Lock threads with semaphore
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *_Nullable responseData, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            if (!error) {
                NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];

                NSMutableDictionary *parts = [responseString dictionaryFromQueryStringComponents];

                if (parts) {
                    NSMutableDictionary *videoDictionary = [NSMutableDictionary dictionary];

                    NSString *player_response = [parts[@"player_response"] firstObject];
                    if (player_response) {
                        NSError *jerr = nil;
                        NSDictionary *player_dict = [NSJSONSerialization JSONObjectWithData:[player_response dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:&jerr];
                        NSLog(@"player_dict: %@",  player_dict[@"streamingData"]);

                        NSArray<NSDictionary *> *formats = player_dict[@"streamingData"][@"adaptiveFormats"];
                        [formats enumerateObjectsUsingBlock:^(NSDictionary *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                            if ([obj[@"mimeType"] rangeOfString:@"video/mp4"].length > 0) {
                                videoDictionary[obj[@"quality"]] = obj[@"url"];
                            }
                        }];
                    }

                    data = videoDictionary;

//                    NSString *fmtStreamMapString = [[parts objectForKey:@"url_encoded_fmt_stream_map"] objectAtIndex:0];
//                    if (fmtStreamMapString.length > 0) {
//
//                        NSArray *fmtStreamMapArray = [fmtStreamMapString componentsSeparatedByString:@","];
//                        NSMutableDictionary *videoDictionary = [NSMutableDictionary dictionary];
//
//                        for (NSString *videoEncodedString in fmtStreamMapArray) {
//                            NSMutableDictionary *videoComponents = [videoEncodedString dictionaryFromQueryStringComponents];
//                            NSString *type = [[[videoComponents objectForKey:@"type"] objectAtIndex:0] stringByDecodingURLFormat];
//                            NSString *signature = nil;
//
//                            if (![videoComponents objectForKey:@"stereo3d"]) {
//                                if ([videoComponents objectForKey:@"itag"]) {
//                                    signature = [[videoComponents objectForKey:@"itag"] objectAtIndex:0];
//                                }
//
//                                if (signature && [type rangeOfString:@"mp4"].length > 0) {
//                                    NSString *url = [[[videoComponents objectForKey:@"url"] objectAtIndex:0] stringByDecodingURLFormat];
//                                    url = [NSString stringWithFormat:@"%@&signature=%@", url, signature];
//
//                                    NSString *quality = [[[videoComponents objectForKey:@"quality"] objectAtIndex:0] stringByDecodingURLFormat];
//                                    if ([videoComponents objectForKey:@"stereo3d"] && [[videoComponents objectForKey:@"stereo3d"] boolValue]) {
//                                        quality = [quality stringByAppendingString:@"-stereo3d"];
//                                    }
//                                    if([videoDictionary valueForKey:quality] == nil) {
//                                        [videoDictionary setObject:url forKey:quality];
//                                    }
//                                }
//
//                            }
//                        }
//
//                        // add some extra information about this video to the dictionary we pass back to save on the amounts of network requests
//                        if (videoDictionary.count > 0)
//                        {
//                            NSMutableDictionary *optionsDict = [NSMutableDictionary dictionary];
////                            NSArray *keys = @[//@"author", // youtube channel name
////                                              //@"avg_rating", // average ratings on yt when downloaded
////                                              @"iurl", //@"iurlmaxres", @"iurlsd", // thumbnail urls
////                                              //@"keywords", // author defined keywords
////                                              @"length_seconds", // total duration in seconds
////                                              @"title", // video title
////                                              //@"video_id"
////                                              ]; // youtube id
////
////                            for (NSString *key in keys)
////                            {
////                                [optionsDict setObject:parts[key][0] forKey:key]; // [0] because we want the object and not the array
////                            }
////
//                            [videoDictionary setObject:optionsDict forKey:@"moreInfo"];
//                        }
//
//                        data = videoDictionary;
//                    }
//                    // Check for live data
//                    else if ([parts objectForKey:@"live_playback"] != nil && [parts objectForKey:@"hlsvp"] != nil && [[parts objectForKey:@"hlsvp"] count] > 0) {
//                        data = @{ @"live": [parts objectForKey:@"hlsvp"][0] };
//                    }
                }
            }
            dispatch_semaphore_signal(semaphore);
        }] resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

        return data;
    }
    return nil;
}

+ (NSDictionary *)h264videosWithYoutubeURL:(NSURL *)youtubeURL {
    NSString *youtubeID = [self youtubeIDFromYoutubeURL:youtubeURL];
    return [self h264videosWithYoutubeID:youtubeID];
}

+ (void)h264videosWithYoutubeURL:(NSURL *)youtubeURL
                   completeBlock:(void (^)(NSDictionary *videoDictionary, NSError *error))completeBlock {
    NSString *youtubeID = [self youtubeIDFromYoutubeURL:youtubeURL];
    if (youtubeID) {
        dispatch_queue_t queue = dispatch_queue_create("me.hiddencode.yt.backgroundqueue", 0);
        dispatch_async(queue, ^{
            NSDictionary *dict = [[self class] h264videosWithYoutubeID:youtubeID];
            dispatch_async(dispatch_get_main_queue(), ^{
                completeBlock(dict, nil);
            });
        });
    } else {
        completeBlock(nil, [NSError errorWithDomain:@"me.hiddencode.yt-parser" code:1001 userInfo:@{ NSLocalizedDescriptionKey: @"Invalid YouTube URL" }]);
    }
}

+ (void)audioM4aInYoutubeID:(NSString *)vid completeBlock:(void (^)(NSArray<NSDictionary *> *, NSError *))completeBlock {
    if (vid) {
        dispatch_queue_t queue = dispatch_queue_create("me.hiddencode.yt.backgroundqueue", 0);
        dispatch_async(queue, ^{
            NSArray<NSDictionary *> *info = [[self class] audioM4aWithYoutubeID:vid];
            dispatch_async(dispatch_get_main_queue(), ^{
                completeBlock(info, nil);
            });
        });
    } else {
        completeBlock(nil, [NSError errorWithDomain:@"com.hzmc.gotube" code:1001 userInfo:@{ NSLocalizedDescriptionKey: @"Invalid vid" }]);
    }
}

+ (void)thumbnailForYoutubeURL:(NSURL *)youtubeURL
                 thumbnailSize:(YouTubeThumbnail)thumbnailSize
                 completeBlock:(void (^)(HCImage *image, NSError *error))completeBlock {
    NSString *youtubeID = [self youtubeIDFromYoutubeURL:youtubeURL];
    return [self thumbnailForYoutubeID:youtubeID thumbnailSize:thumbnailSize completeBlock:completeBlock];
}

+ (NSURL *)thumbnailUrlForYoutubeURL:(NSURL *)youtubeURL
                       thumbnailSize:(YouTubeThumbnail)thumbnailSize {
    NSURL *url = nil;

    if (youtubeURL) {
        NSString *thumbnailSizeString = nil;
        switch (thumbnailSize) {
            case YouTubeThumbnailDefault:
                thumbnailSizeString = @"default";
                break;
            case YouTubeThumbnailDefaultMedium:
                thumbnailSizeString = @"mqdefault";
                break;
            case YouTubeThumbnailDefaultHighQuality:
                thumbnailSizeString = @"hqdefault";
                break;
            case YouTubeThumbnailDefaultMaxQuality:
                thumbnailSizeString = @"maxresdefault";
                break;
            default:
                thumbnailSizeString = @"default";
                break;
        }
        NSString *youtubeID = [self youtubeIDFromYoutubeURL:youtubeURL];
        url = [NSURL URLWithString:[NSString stringWithFormat:kYoutubeThumbnailURL, youtubeID, thumbnailSizeString]];
    }

    return url;
}

+ (void)thumbnailForYoutubeID:(NSString *)youtubeID thumbnailSize:(YouTubeThumbnail)thumbnailSize completeBlock:(void (^)(HCImage *, NSError *))completeBlock {
    if (youtubeID) {
        NSString *thumbnailSizeString = nil;
        switch (thumbnailSize) {
            case YouTubeThumbnailDefault:
                thumbnailSizeString = @"default";
                break;
            case YouTubeThumbnailDefaultMedium:
                thumbnailSizeString = @"mqdefault";
                break;
            case YouTubeThumbnailDefaultHighQuality:
                thumbnailSizeString = @"hqdefault";
                break;
            case YouTubeThumbnailDefaultMaxQuality:
                thumbnailSizeString = @"maxresdefault";
                break;
            default:
                thumbnailSizeString = @"default";
                break;
        }

        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:kYoutubeThumbnailURL, youtubeID, thumbnailSizeString]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
        [request setHTTPMethod:@"GET"];

        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            if (!error) {
                HCImage *image = [[HCImage alloc] initWithData:data];
                completeBlock(image, nil);
            } else {
                completeBlock(nil, error);
            }
        }] resume];
    } else {
        NSDictionary *details = @{ NSLocalizedDescriptionKey: @"Could not find a valid Youtube ID" };
        NSError *error = [NSError errorWithDomain:@"com.hiddencode.yt-parser" code:0 userInfo:details];
        completeBlock(nil, error);
    }
}

+ (void)detailsForYouTubeURL:(NSURL *)youtubeURL
               completeBlock:(void (^)(NSDictionary *details, NSError *error))completeBlock {
    NSString *youtubeID = [self youtubeIDFromYoutubeURL:youtubeURL];
    if (youtubeID) {
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:kYoutubeDataURL, youtubeID]]];

        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            if (!error) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                     options:kNilOptions
                                                                       error:&error];
                if (!error) {
                    completeBlock(json, nil);
                } else {
                    completeBlock(nil, error);
                }
            } else {
                completeBlock(nil, error);
            }
        }] resume];
    } else {
        NSDictionary *details = @{ NSLocalizedDescriptionKey: @"Could not find a valid Youtube ID" };
        NSError *error = [NSError errorWithDomain:@"com.hiddencode.yt-parser" code:0 userInfo:details];
        completeBlock(nil, error);
    }
}

@end
