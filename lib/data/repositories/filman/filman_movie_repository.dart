import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_dio_factory.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:purevideo/di/injection_container.dart';

class FilmanMovieRepository implements MovieRepository {
  final AuthRepository _authRepository =
      getIt<Map<SupportedService, AuthRepository>>()[SupportedService.filman]!;
  Dio? _dio;

  FilmanMovieRepository() {
    _authRepository.authStream.listen(_onAuthChanged);
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.filman) {
      _dio = FilmanDioFactory.getDio(auth.account);
    }
  }

  Future<void> _prepareDio() async {
    if (_dio == null) {
      final account = _authRepository.getAccount();
      _dio = FilmanDioFactory.getDio(account);
    }
  }

  Future<String> _resolveTempUrl(String tempUrl) async {
    try {
      final response = await Dio().get(
        tempUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 16; Pixel 8 Build/BP31.250610.004; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36',
          },
        ),
      );

      final String body = response.data.toString();

      RegExp regExp = RegExp(r'''var _e\s*=\s*['"]([A-Za-z0-9+/=]+)['"]''');
      RegExp regExpA = RegExp(r'''var _a\s*=\s*['"]([^'"]+)['"]''');
      RegExp regExpB = RegExp(r'''var _b\s*=\s*['"]([^'"]+)['"]''');
      RegExp regExpC = RegExp(r'''var _c\s*=\s*['"]([^'"]+)['"]''');

      Match? matchE = regExp.firstMatch(body);
      Match? matchA = regExpA.firstMatch(body);
      Match? matchB = regExpB.firstMatch(body);
      Match? matchC = regExpC.firstMatch(body);

      if (matchE != null &&
          matchA != null &&
          matchB != null &&
          matchC != null) {
        String encoded = matchE.group(1)!;
        String key = matchA.group(1)! + matchB.group(1)! + matchC.group(1)!;

        debugPrint('Encoded found: $encoded');
        debugPrint('Key: $key');

        try {
          List<int> raw = base64.decode(encoded);
          List<int> keyBytes = key.codeUnits;
          String result = String.fromCharCodes(
            List.generate(
                raw.length, (i) => raw[i] ^ keyBytes[i % keyBytes.length]),
          );

          debugPrint('Decoded URL: $result');
          return result;
        } catch (e) {
          debugPrint('XOR decode failed: $e');
          return '';
        }
      } else {
        debugPrint('Could not find _e/_a/_b/_c in body');
        return '';
      }
    } catch (e) {
      debugPrint('Failed to resolve temp URL: $tempUrl - ${e.toString()}');
      return tempUrl;
    }
  }

  Future<List<HostLink>> _extractHostLinksFromDocument(
      dom.Document document) async {
    final videoUrls = <HostLink>[];

    for (final row in document.querySelectorAll('tbody tr')) {
      String? link;

      try {
        final decoded = base64Decode(
            row.querySelector('a[data-iframe]')?.attributes['data-iframe'] ??
                '');
        link = (utf8.decode(decoded));
      } catch (e) {
        debugPrint(
            'Failed to decode link: ${row.querySelector('a[data-iframe]')?.attributes['data-iframe']} - ${e.toString()}');
        link = null;
      }

      if (link == null || link.isEmpty == true) continue;

      if (link.contains('tmp-url.pro')) {
        link = await _resolveTempUrl(link);
        debugPrint('Resolved temp URL to: $link');
      }

      final tableData = row.querySelectorAll('td');
      if (tableData.length < 3) continue;
      final language = tableData[1].text.trim();
      final qualityVersion = tableData[2].text.trim();

      videoUrls.add(HostLink(
        url: link,
        lang: language,
        quality: qualityVersion,
      ));
    }

    return videoUrls;
  }

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    await _prepareDio();

    final response = await _dio!.get('/');
    final document = html.parse(response.data);

    final movies = <ServiceMovieModel>[];

    for (final list in document.querySelectorAll('div[id=item-list]')) {
      for (final item in list.children) {
        final poster = item.querySelector('.poster');
        final title = poster
                ?.querySelector('a')
                ?.attributes['title']
                ?.trim()
                .split('/')
                .first
                .trim() ??
            'Brak danych';
        final imageUrl = poster?.querySelector('img')?.attributes['data-src'] ??
            'https://placehold.co/250x370/png?font=roboto&text=?';
        final link =
            poster?.querySelector('a')?.attributes['href'] ?? 'Brak danych';
        final category =
            list.parent?.querySelector('h3')?.text.trim() ?? 'INNE';

        final movie = ServiceMovieModel(
          service: SupportedService.filman,
          title: title,
          imageUrl: imageUrl,
          url: link,
          category: category,
        );

        movies.add(movie);
      }
    }

    return movies;
  }

  Future<List<HostLink>> _scrapeEpisodeVideoUrls(String episodeUrl) async {
    await _prepareDio();

    final response = await _dio!.get(episodeUrl);
    final document = html.parse(response.data);

    final hostLinks = await _extractHostLinksFromDocument(document);

    return hostLinks;
  }

  String _prepareTitle(String title) {
    return title.contains('/') ? title.split('/').first.trim() : title.trim();
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    await _prepareDio();

    final response = await _dio!.get(url);
    final document = html.parse(response.data);

    final title = _prepareTitle(document
            .querySelector('[itemprop="name"]')
            ?.text
            .replaceAll(
                document.querySelector('[itemprop="name"] *')?.text ?? '',
                '') ??
        'Brak tytułu');
    final description =
        document.querySelector('.description')?.text.trim() ?? '';
    final imageUrl =
        document.querySelector('#single-poster img')?.attributes['src'] ?? '';

    final episodeList = document.querySelector('#episode-list');
    final isSeries = episodeList != null;

    if (isSeries) {
      final seasons = <SeasonModel>[];
      for (int i = 0; i < episodeList.children.length; i++) {
        final seasonElement = episodeList.children[i];
        final episodes = <EpisodeModel>[];

        for (int j = 0; j < seasonElement.children.last.children.length; j++) {
          final episodeElement = seasonElement.children.last.children[j];
          final episodeTitle =
              episodeElement.text.trim().split(' ').skip(1).join(' ');
          final episodeUrl =
              episodeElement.querySelector('a')?.attributes['href'];

          if (episodeUrl == null) {
            continue;
          }

          episodes.add(
            EpisodeModel(
                title: episodeTitle,
                number: seasonElement.children.last.children.length - j,
                url: episodeUrl,
                videoUrls: []),
          );
        }

        seasons.add(SeasonModel(
            number: episodeList.children.length - i,
            episodes: episodes.toList().reversed.toList()));
      }

      return ServiceMovieDetailsModel(
        service: SupportedService.filman,
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        isSeries: isSeries,
        seasons: seasons.toList().reversed.toList(),
      );
    }

    final videoUrls = await _extractHostLinksFromDocument(document);

    final movieModel = ServiceMovieDetailsModel(
      service: SupportedService.filman,
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      isSeries: isSeries,
      videoUrls: videoUrls,
    );

    return movieModel;
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    final videoUrls = await _scrapeEpisodeVideoUrls(episode.url);
    return episode.copyWith(videoUrls: videoUrls);
  }
}
