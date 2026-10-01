# =====================================================================
# Tilly - Build des executables sur VPS (Linux)
# =====================================================================
# Ce Dockerfile genere l'APK Android. Il necessite que les secrets de
# signature soient presents dans le contexte de build (copies par
# scripts/build-releases.sh depuis /opt/tilly-secrets/) :
#   - android/key.properties
#   - android/app/tilly-release.jks
#   - android/app/google-services.json
#
# Build :
#   docker build \
#     --build-arg APP_VERSION=1.2.3 \
#     --build-arg BUILD_NUMBER=1002003 \
#     --target artifacts \
#     --output type=local,dest=./out \
#     .
# =====================================================================

FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /src

# Dependances d'abord pour profiter du cache Docker
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Reste du projet (secrets de signature deja places dans le contexte)
COPY . .

# Overrides pour VPS faible en RAM (2 Go) : limite la memoire de Gradle/Kotlin
# (la derniere valeur de chaque cle gagne dans gradle.properties)
RUN printf '\n# VPS low-memory overrides\norg.gradle.jvmargs=-Xmx768m -XX:MaxMetaspaceSize=384m\norg.gradle.daemon=false\norg.gradle.parallel=false\norg.gradle.workers.max=1\norg.gradle.vfs.watch=false\nkotlin.compiler.execution.strategy=in-process\nkotlin.daemon.jvmargs=-Xmx384m\n' >> android/gradle.properties

ARG APP_VERSION
ARG BUILD_NUMBER

RUN flutter pub get \
    && flutter build apk --release \
        --build-name="${APP_VERSION}" \
        --build-number="${BUILD_NUMBER}" \
        --dart-define=APP_VERSION="${APP_VERSION}"

RUN mkdir -p /artifacts \
    && cp build/app/outputs/flutter-apk/app-release.apk \
        "/artifacts/Tilly-Android-${APP_VERSION}.apk"

# Stage final : expose uniquement les artefacts produits
FROM scratch AS artifacts
COPY --from=builder /artifacts/ /artifacts/
