include { BUNDLE_BUNDLEPARC } from '../../../modules/nf-neuro/bundle/bundleparc/main.nf'
include { IMAGE_INFO } from '../../../modules/nf-neuro/image/info/main.nf'

def compute_file_hash(file_path) {
    def file = new File(file_path)
    if (!file.exists()) {
        error "File not found: $file_path"
    }

    def digest = java.security.MessageDigest.getInstance("MD5")
    def fileBytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(file_path))
    def hashBytes = digest.digest(fileBytes)
    return hashBytes.collect { value -> String.format("%02x", value) }.join('')
}

def fetch_bundleparc_checkpoint(dest) {
    def checkpoint_url = "https://zenodo.org/records/19634429/files/123_4_5.ckpt"
    def checkpoint_md5 = "cfd908daea4c0a5aa0517a192dd9f845"

    if (file("$workflow.workDir/checkpoint/123_4_5_bundleparc.ckpt").exists()) {
        def existing_md5 = compute_file_hash("$workflow.workDir/checkpoint/123_4_5_bundleparc.ckpt")
        if (existing_md5 == checkpoint_md5) {
            println "BundleParc checkpoint already exists and is valid."
            return "$workflow.workDir/checkpoint/123_4_5_bundleparc.ckpt"
        } else {
            println "Existing BundleParc checkpoint is invalid. Re-downloading..."
            new File("$workflow.workDir/checkpoint/123_4_5_bundleparc.ckpt").delete()
        }
    }

    def path = java.nio.file.Paths.get("$dest/checkpoint/")
    if (!java.nio.file.Files.exists(path)) {
        java.nio.file.Files.createDirectories(path)
    }

    println("Downloading BundleParc checkpoint from $checkpoint_url...")
    def checkpoint = new File("$dest/checkpoint/123_4_5_bundleparc.ckpt").withOutputStream { out ->
        new URL(checkpoint_url).withInputStream { from -> out << from; }
    }
    println("Download completed.")

    return checkpoint
}

workflow BUNDLEPARC {

    take:
        ch_fodf // channel: [ val(meta), [ fodf ] ] or [ fodf ]

    main:
        ch_versions = channel.empty()

        checkpoint_path = null
        if ( params.bundleparc_checkpoint ) {
            checkpoint_path = file("$params.bundleparc_checkpoint", checkIfExists: true)
        }
        else {
            if ( !file("$workflow.workDir/checkpoint/123_4_5_bundleparc.ckpt").exists() ) {
                fetch_bundleparc_checkpoint("${workflow.workDir}/")
            }
            checkpoint_path = file("$workflow.workDir/checkpoint/123_4_5_bundleparc.ckpt", checkIfExists: true)
        }

        ch_fodf_bundleparc = ch_fodf
            .combine(channel.value(checkpoint_path))
            .map { meta, fodf, checkpoint -> [meta, fodf instanceof List ? fodf[0] : fodf, checkpoint] }

        ch_fodf_info = ch_fodf
            .map { meta, fodf -> [meta, fodf instanceof List ? fodf[0] : fodf] }

        IMAGE_INFO(ch_fodf_info)
        ch_versions = ch_versions.mix(IMAGE_INFO.out.versions)

        ch_stride_check = IMAGE_INFO.out.property.map { meta, property_output ->
            def matcher = (property_output =~ /Data strides:\s*\[\s*([^\]]+)\s*\]/)
            def strides = matcher ? matcher[0][1] : property_output
            def normalized_strides = strides.trim().replaceAll(/\s+/, ' ')

            if (normalized_strides != '-1 2 3 4') {
                error "Invalid fODF strides for ${meta.id}: '${normalized_strides}'. Expected '-1 2 3 4'."
            }

            return [meta, true]
        }

        ch_fodf_bundleparc = ch_fodf_bundleparc
            .join(ch_stride_check)
            .map { meta, fodf, checkpoint, _ok -> [meta, fodf, checkpoint] }

        BUNDLE_BUNDLEPARC(ch_fodf_bundleparc)
        ch_versions = ch_versions.mix(BUNDLE_BUNDLEPARC.out.versions)

    emit:
        bundles     = BUNDLE_BUNDLEPARC.out.labels // channel: [ val(meta), [ bundles ] ]
        versions    = ch_versions                  // channel: [ versions.yml ]
}
