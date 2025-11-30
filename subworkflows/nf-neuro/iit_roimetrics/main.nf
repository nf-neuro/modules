include { ATLAS_IIT              } from '../../nf-neuro/atlas_iit/main'
include { REGISTRATION_ANTS as REGISTER_ATLAS_B0 } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_ATLAS_BUNDLES } from '../../../modules/nf-neuro/registration/antsapplytransforms/main.nf'
include { STATS_METRICSINROI     } from '../../../modules/nf-neuro/stats/metricsinroi/main'

workflow IIT_ROIMETRICS {
    take:
    ch_b0       // channel : [required] meta, b0
    ch_metrics  // channel : [required] meta, [metrics]

    main:
    ch_versions             = channel.empty()

    ATLAS_IIT()
    ch_versions = ch_versions.mix(ATLAS_IIT.out.versions)

    // Register IIT atlas to subject space
    ch_input_register_iit = ch_b0
        .combine(ATLAS_IIT.out.b0)
        .map{ meta, b0, template_b0 -> [meta, b0, template_b0, []] }
    REGISTER_ATLAS_B0(ch_input_register_iit)
    ch_versions = ch_versions.mix(REGISTER_ATLAS_B0.out.versions)

    // Apply the transformation to subject space to the bundles
    ch_iit_transform_bundles = ch_b0
        .join(REGISTER_ATLAS_B0.out.forward_image_transform)
        .combine(ATLAS_IIT.out.bundle_masks.toList())
        .map {
            meta, b0, transform, bundles ->
                [meta, bundles, b0, transform]
        }
    TRANSFORM_ATLAS_BUNDLES(ch_iit_transform_bundles)
    ch_versions = ch_versions.mix(TRANSFORM_ATLAS_BUNDLES.out.versions)

    //
    // EXTRACT ROI VOLUME STATISTICS
    //
    // Input: [meta, [metrics_list], [masks]]
    ch_input_metricsinroi = ch_metrics
        .join(TRANSFORM_ATLAS_BUNDLES.out.warped_image)
        .map {
            meta, metrics, masks ->
                [meta, metrics, masks, []]
        }

    STATS_METRICSINROI(ch_input_metricsinroi)
    ch_versions = ch_versions.mix(STATS_METRICSINROI.out.versions)

    emit:
    json        = STATS_METRICSINROI.out.stats_json
    tab_mean    = STATS_METRICSINROI.out.stats_mean
    tab_std     = STATS_METRICSINROI.out.stats_std

    versions        = ch_versions
}
