include { BUNDLE_RECOGNIZE  } from '../../../modules/nf-neuro/bundle/recognize/main'

include { REGISTRATION } from '../registration/main'

def fetch_bundleseg_atlas(atlasUrl, configUrl, dest) {

    def atlas = new File("$dest/atlas.zip").withOutputStream{ out ->
        new URL(atlasUrl).withInputStream { from -> out << from; }
    }

    def config = new File("$dest/config.zip").withOutputStream{ out ->
        new URL(configUrl).withInputStream { from -> out << from; }
    }

    def atlasFile = new java.util.zip.ZipFile("$dest/atlas.zip")
    atlasFile.entries().each{ it ->
        def path = java.nio.file.Paths.get("$dest/atlas/" + it.name)
        if(it.directory){
            java.nio.file.Files.createDirectories(path)
        }
        else {
            def parentDir = path.getParent()
            if (!java.nio.file.Files.exists(parentDir)) {
                java.nio.file.Files.createDirectories(parentDir)
            }
            java.nio.file.Files.copy(atlasFile.getInputStream(it), path)
        }
    }

    def configFile = new java.util.zip.ZipFile("$dest/config.zip")
    configFile.entries().each{ it ->
        def path = java.nio.file.Paths.get("$dest/config/" + it.name)
        if(it.directory){
            java.nio.file.Files.createDirectories(path)
        }
        else {
            def parentDir = path.getParent()
            if (!java.nio.file.Files.exists(parentDir)) {
                java.nio.file.Files.createDirectories(parentDir)
            }
            java.nio.file.Files.copy(configFile.getInputStream(it), path)
        }
    }
}

workflow BUNDLE_SEG {
    take:
        ch_fa                   // channel: [ val(meta), [ fa ] ]
        ch_tractogram           // channel: [ val(meta), [ tractogram ] ]
        ch_freesurfer_license   // channel: [ val(meta), path(fs_license) ]
    main:
        if ( params.run_easyreg ) error "The BUNDLE_SEG workflow does not support the easyreg registration method."
        if ( params.run_synthmorph ) {
            ch_freesurfer_license.ifEmpty{ error "Synthmorph registration need a Freesurfer License to run." }
        }

        ch_versions = channel.empty()
        ch_mqc = channel.empty()

        // ** Setting up Atlas reference channels. ** //
        if ( params.atlas_directory ) {
            ch_atlas_anat = channel.fromPath("$params.atlas_directory/atlas/mni_masked.nii.gz", checkIfExists: true, relative: true)
            ch_atlas_config = channel.fromPath("$params.atlas_directory/config/config_fss_1.json", checkIfExists: true, relative: true)
            ch_atlas_average = channel.fromPath("$params.atlas_directory/atlas/atlas/", checkIfExists: true, relative: true)
        }
        else {
            if ( !file("$workflow.workDir/atlas/mni_masked.nii.gz").exists() ) {
                fetch_bundleseg_atlas(
                    "https://zenodo.org/records/10103446/files/atlas.zip?download=1",
                    "https://zenodo.org/records/10103446/files/config.zip?download=1",
                    "${workflow.workDir}/"
                )
            }
            ch_atlas_anat = channel.fromPath("$workflow.workDir/atlas/mni_masked.nii.gz")
            ch_atlas_config = channel.fromPath("$workflow.workDir/config/config_fss_1.json")
            ch_atlas_average = channel.fromPath("$workflow.workDir/atlas/atlas/")
        }

        // ** Register the atlas to subject's space. Set up atlas file as moving image ** //
        // ** and subject anat as fixed image.                                         ** //
        ch_atlas_anat = ch_fa
            .combine(ch_atlas_anat)
            .map{ meta, _fa, anat -> [meta, anat] }

        REGISTRATION(
            ch_fa,
            ch_atlas_anat,
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            ch_freesurfer_license
        )
        ch_versions = ch_versions.mix(REGISTRATION.out.versions.first())
        ch_mqc = ch_mqc.mix(REGISTRATION.out.mqc)

        // ** Perform bundle recognition and segmentation ** //
        ch_recognize_bundle = ch_tractogram
            .join(REGISTRATION.out.forward_affine)
            .combine(ch_atlas_config)
            .combine(ch_atlas_average)

        BUNDLE_RECOGNIZE ( ch_recognize_bundle )
        ch_versions = ch_versions.mix(BUNDLE_RECOGNIZE.out.versions.first())
    emit:
        bundles = BUNDLE_RECOGNIZE.out.bundles              // channel: [ val(meta), [ bundles ] ]
        mqc = ch_mqc                                        // channel: [ *mqc.* ]
        bundles_mqc = BUNDLE_RECOGNIZE.out.bundles_mqc      // channel: [ *_bundles_mosaic_mqc.png ]
        stats_mqc = BUNDLE_RECOGNIZE.out.stats_mqc          // channel: [ *_bundles_stats_mqc.json ]
        versions = ch_versions                              // channel: [ versions.yml ]
}
